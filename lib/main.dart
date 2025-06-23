import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings settings = InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(settings);
  runApp(const ToDoApp());
}

class ToDoApp extends StatelessWidget {
  const ToDoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'To-Do List',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.indigo,
        ),
        useMaterial3: true,
      ),
      home: const ToDoHomePage(),
    );
  }
}

class Task {
  String text;
  bool done;
  DateTime deadline;

  Task({required this.text, this.done = false, required this.deadline});

  Map<String, dynamic> toJson() => {
        'text': text,
        'done': done,
        'deadline': deadline.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        text: json['text'],
        done: json['done'],
        deadline: DateTime.parse(json['deadline']),
      );
}

Future<void> _scheduleNotification(
    int id, String title, String body, DateTime scheduledTime) async {
  await flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    title,
    body,
    tz.TZDateTime.from(scheduledTime, tz.local),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'reminder_channel',
        'Task Reminders',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
    androidAllowWhileIdle: true,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.dateAndTime,
  );
}

Future<void> _scheduleReminders(Task task, int taskId) async {
  final now = DateTime.now();
  final deadline = task.deadline;

  if (task.done) return;

  if (now.year == deadline.year &&
      now.month == deadline.month &&
      now.day == deadline.day) {
    final morning = DateTime(deadline.year, deadline.month, deadline.day, 8);
    if (now.isBefore(morning)) {
      await _scheduleNotification(
          taskId * 100,
          'Reminder: ${task.text}',
          'Deadline today at ${DateFormat('hh:mm a').format(deadline)}',
          morning);
    }

    final hoursBefore = deadline.subtract(const Duration(hours: 4));
    if (now.isBefore(hoursBefore)) {
      for (int i = 3; i >= 1; i--) {
        final time = deadline.subtract(Duration(hours: i));
        if (time.isAfter(now)) {
          await _scheduleNotification(
              taskId * 10 + i,
              'Upcoming Task',
              '${task.text} is due at ${DateFormat('hh:mm a').format(deadline)}',
              time);
        }
      }
    }
  } else if (now.isBefore(deadline)) {
    final morning = DateTime(deadline.year, deadline.month, deadline.day, 8);
    await _scheduleNotification(
        taskId * 100,
        'Reminder: ${task.text}',
        'Deadline today at ${DateFormat('hh:mm a').format(deadline)}',
        morning);

    DateTime next = morning.add(const Duration(hours: 2));
    int count = 1;
    while (next.isBefore(deadline)) {
      await _scheduleNotification(
          taskId * 10 + count,
          'Reminder: ${task.text}',
          'Due at ${DateFormat('hh:mm a').format(deadline)}',
          next);
      next = next.add(Duration(hours: 2 + (count % 2)));
      count++;
    }
  }
}

class ToDoHomePage extends StatefulWidget {
  const ToDoHomePage({super.key});

  @override
  _ToDoHomePageState createState() => _ToDoHomePageState();
}

class _ToDoHomePageState extends State<ToDoHomePage> {
  final TextEditingController _controller = TextEditingController();
  final List<Task> _tasks = <Task>[];
  final Set<int> _selectedIndexes = <int>{};
  bool _isSelectionMode = false;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> storedTasks = prefs.getStringList('tasks') ?? [];
    setState(() {
      _tasks.clear();
      _tasks.addAll(storedTasks.map((String t) => Task.fromJson(jsonDecode(t))));
    });
  }

  Future<void> _saveTasks() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> taskJsonList =
        _tasks.map((task) => jsonEncode(task.toJson())).toList();
    await prefs.setStringList('tasks', taskJsonList);
  }

  void _addTask(String text, [DateTime? deadline]) {
    if (text.isEmpty) return;
    final DateTime effectiveDeadline;
    if (deadline == null) {
      final DateTime now = DateTime.now();
      effectiveDeadline = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else {
      effectiveDeadline = deadline;
    }

    setState(() {
      _tasks.add(Task(text: text, deadline: effectiveDeadline));
    });
    _scheduleReminders(_tasks.last, _tasks.length - 1);
    _controller.clear();
    _saveTasks();
  }

  // ... rest of your code remains unchanged.

  void _toggleTask(int index) {
    setState(() {
      _tasks[index].done = !_tasks[index].done;
    });
    _saveTasks();
  }

  void _deleteTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
    _saveTasks();
  }

  void _deleteSelectedTasks() {
    setState(() {
      final List<int> indexesToDelete = _selectedIndexes.toList();
      indexesToDelete.sort((int a, int b) => b.compareTo(a));
      for (final int index in indexesToDelete) {
        _tasks.removeAt(index);
      }
      _selectedIndexes.clear();
      _isSelectionMode = false;
    });
    _saveTasks();
  }

  void _toggleSelection(int index) {
    setState(() {
      _selectedIndexes.contains(index)
          ? _selectedIndexes.remove(index)
          : _selectedIndexes.add(index);
    });
  }

  void _enableSelectionMode() {
    setState(() => _isSelectionMode = true);
  }

  void _cancelSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIndexes.clear();
    });
  }

  void _editTask(int index) async {
    final TextEditingController editedController =
        TextEditingController(text: _tasks[index].text);
    DateTime newDeadline = _tasks[index].deadline;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Edit Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(controller: editedController),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () async {
                    final DateTime? date = await showDatePicker(
                      context: dialogContext,
                      initialDate: newDeadline,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      final TimeOfDay? time = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(newDeadline),
                      );
                      if (time != null) {
                        newDeadline = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Edit Deadline'),
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              setState(() {
                _tasks[index].text = editedController.text;
                _tasks[index].deadline = newDeadline;
              });
              Navigator.of(dialogContext).pop();
              _saveTasks();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  List<Task> get filteredTasks {
    final DateTime now = DateTime.now();
    final DateTime endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return _tasks.where((Task task) {
      switch (_filter) {
        case 'Today':
          return task.deadline.day == now.day &&
              task.deadline.month == now.month &&
              task.deadline.year == now.year;
        case 'Pending':
          return !task.done;
        case 'Completed':
          return task.done;
        case 'Overdue':
          return !task.done && task.deadline.isBefore(DateTime.now());
        case 'Deadlines':
          return task.deadline.isAfter(endOfToday);
        default:
          return true;
      }
    }).toList();
  }

  String formatDeadline(DateTime deadline) {
    return DateFormat('dd MMM, hh:mm a').format(deadline);
  }

  Widget statusChip(Task task) {
    if (task.done) {
      return Chip(label: const Text('Completed'), backgroundColor: Colors.green[300]);
    } else if (task.deadline.isBefore(DateTime.now())) {
      return Chip(label: const Text('Overdue'), backgroundColor: Colors.red[300]);
    } else {
      return Chip(label: const Text('Pending'), backgroundColor: Colors.orange[300]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? 'Selected (${_selectedIndexes.length})' : 'To-Do List'),
        actions: _isSelectionMode
            ? [
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelectedTasks),
                IconButton(icon: const Icon(Icons.cancel), onPressed: _cancelSelectionMode),
              ]
            : [],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'Enter task',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      onPressed: () => _addTask(_controller.text),
                      child: const Text('Add Task'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_controller.text.isEmpty) return;
                        final DateTime? date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        DateTime? deadline;
                        if (date != null) {
                          final TimeOfDay? time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            deadline = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          }
                        }
                        _addTask(_controller.text, deadline);
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add with Reminder'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _enableSelectionMode,
                      child: const Text('Select'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Today', 'Pending', 'Completed', 'Overdue', 'Deadlines']
                  .map((String type) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ChoiceChip(
                          label: Text(type),
                          selected: _filter == type,
                          onSelected: (bool selected) => setState(() => _filter = type),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: filteredTasks.length,
              itemBuilder: (BuildContext context, int index) {
                final Task task = filteredTasks[index];
                final int originalIndex = _tasks.indexOf(task);
                final bool selected = _selectedIndexes.contains(originalIndex);

                return Dismissible(
                  key: Key(task.text + originalIndex.toString()),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => _deleteTask(originalIndex),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  child: Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                    child: ListTile(
                      onTap: _isSelectionMode ? () => _toggleSelection(originalIndex) : null,
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _enableSelectionMode();
                          _toggleSelection(originalIndex);
                        }
                      },
                      tileColor: selected ? Colors.indigo.withOpacity(0.2) : null,
                      title: Text(
                        task.text,
                        style: TextStyle(
                          decoration: task.done ? TextDecoration.lineThrough : null,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text('Due: ${formatDeadline(task.deadline)}'),
                      leading: Checkbox(
                        value: task.done,
                        onChanged: (_) => _toggleTask(originalIndex),
                      ),
                      trailing: Wrap(
                        spacing: 10,
                        children: [
                          statusChip(task),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editTask(originalIndex),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
