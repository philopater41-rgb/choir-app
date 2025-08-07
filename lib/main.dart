import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

// --- MODELS ---
// Defining the structure of our data

class Event {
  String name;
  String type; // 'attendance' or 'trip'
  List<dynamic> records;
  String? expiryDate;
  double? totalCost;

  Event({
    required this.name,
    required this.type,
    required this.records,
    this.expiryDate,
    this.totalCost,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'records': records,
        'expiryDate': expiryDate,
        'totalCost': totalCost,
      };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        name: json['name'],
        type: json['type'],
        records: json['records'],
        expiryDate: json['expiryDate'],
        totalCost: json['totalCost']?.toDouble(),
      );
}

// --- MAIN APP ---

void main() {
  runApp(const ChoirApp());
}

class ChoirApp extends StatelessWidget {
  const ChoirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Choir Attendance App',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.cyan,
        fontFamily: 'Tajawal', // Using a nice Arabic font
      ),
      home: const MainPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // This is the main state of our application
  List<String> _members = [];
  List<Event> _events = [];
  bool _isLoading = false;
  String _view = 'main'; // Controls which screen is visible

  // State for current operation
  String _mode = ''; // 'attendance' or 'trip'
  String _eventName = '';
  String? _eventExpiry;
  double? _tripTotalCost;
  
  // State for scanner screen
  final TextEditingController _nameInputController = TextEditingController();

  // State for modals
  final TextEditingController _tripNameController = TextEditingController();
  final TextEditingController _tripTotalController = TextEditingController();
  final TextEditingController _tripPaidController = TextEditingController();
  final TextEditingController _bulkImportController = TextEditingController();
  
  // State for reports
  String? _selectedMember;
  Event? _selectedEvent;


  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- DATA PERSISTENCE ---

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final membersString = prefs.getString('choirApp_members');
    final eventsString = prefs.getString('choirApp_events');

    if (membersString != null) {
      _members = List<String>.from(json.decode(membersString));
    }
    if (eventsString != null) {
      _events = (json.decode(eventsString) as List)
          .map((e) => Event.fromJson(e))
          .toList();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveMembers(List<String> members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('choirApp_members', json.encode(members));
    setState(() => _members = members);
  }

  Future<void> _saveEvents(List<Event> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('choirApp_events', json.encode(events));
    setState(() => _events = events);
  }

  // --- LOGIC ---

  void _handleModeSelect(String mode) {
    if (_members.isEmpty) {
      _showSnackbar("الرجاء إضافة أعضاء أولاً عبر 'استيراد الأعضاء'.", isError: true);
      return;
    }
    setState(() {
      _mode = mode;
      if (mode == 'trip') {
        _view = 'select_trip';
      } else {
        final today = intl.DateFormat.yMMMMd('ar_EG').format(DateTime.now());
        _eventName = "حضور $today";
        _view = 'scanner';
      }
    });
  }

  void _handleBulkImport() {
    final names = _bulkImportController.text
        .split('\n')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();

    if (names.isEmpty) {
      _showSnackbar("الرجاء لصق قائمة الأسماء.", isError: true);
      return;
    }

    final updatedMembers = [...{..._members, ...names}].toList(); // Merge and remove duplicates
    _saveMembers(updatedMembers);
    _showSnackbar("تم استيراد وإضافة ${names.length} اسم بنجاح.");
    _bulkImportController.clear();
    setState(() => _view = 'main');
  }

  void _handleScan() {
    final trimmedName = _nameInputController.text.trim();
    if (trimmedName.isEmpty) {
      _showSnackbar("الرجاء إدخال الاسم.", isError: true);
      return;
    }
    if (!_members.contains(trimmedName)) {
      _showSnackbar("هذا العضو غير مسجل!", isError: true);
      return;
    }
    
    if (_mode == 'trip') {
      _showPaymentDialog(trimmedName);
    } else {
      _processAttendance(trimmedName);
    }
  }

  void _processAttendance(String name) {
    final updatedEvents = List<Event>.from(_events);
    var event = updatedEvents.firstWhere((e) => e.name == _eventName, orElse: () {
      final newEvent = Event(name: _eventName, type: 'attendance', records: []);
      updatedEvents.add(newEvent);
      return newEvent;
    });

    final alreadyAttended = event.records.any((r) => r['name'] == name);
    if (alreadyAttended) {
      _showSnackbar("هذا العضو مسجل بالفعل اليوم.", isError: true);
      return;
    }

    final timestamp = intl.DateFormat.yMMMMEEEEd('ar_EG').add_jms().format(DateTime.now());
    event.records.add({'name': name, 'timestamp': timestamp});
    _saveEvents(updatedEvents);
    
    // For confirmation screen
    _selectedEvent = Event(name: _eventName, type: 'attendance', records: [{'الاسم': name, 'وقت الحضور': timestamp}]);

    setState(() {
      _view = 'confirmation';
    });
  }

  void _processPayment(String name, double newPayment) {
     final updatedEvents = List<Event>.from(_events);
     var event = updatedEvents.firstWhere((e) => e.name == _eventName);

     var record = event.records.firstWhere((r) => r['name'] == name, orElse: () => null);

     if (record != null) {
       final previousPaid = double.tryParse(record['paid'].replaceAll(' ج.م', '')) ?? 0.0;
       final newTotalPaid = previousPaid + newPayment;
       final remaining = (_tripTotalCost! - newTotalPaid).clamp(0, double.infinity);
       record['paid'] = "${newTotalPaid.toStringAsFixed(2)} ج.م";
       record['remaining'] = "${remaining.toStringAsFixed(2)} ج.م";
       record['history'].add({'amount': "${newPayment.toStringAsFixed(2)} ج.م", 'date': intl.DateFormat.yMd('ar_EG').add_jm().format(DateTime.now())});
     } else {
       final remaining = (_tripTotalCost! - newPayment).clamp(0, double.infinity);
       record = {
         'name': name,
         'total': "${_tripTotalCost!.toStringAsFixed(2)} ج.م",
         'paid': "${newPayment.toStringAsFixed(2)} ج.م",
         'remaining': "${remaining.toStringAsFixed(2)} ج.م",
         'history': [{'amount': "${newPayment.toStringAsFixed(2)} ج.م", 'date': intl.DateFormat.yMd('ar_EG').add_jm().format(DateTime.now())}]
       };
       event.records.add(record);
     }
     
     _saveEvents(updatedEvents);

     _selectedEvent = Event(name: _eventName, type: 'trip', records: [
       {
         'الاسم': name,
         'الدفعة الحالية': "${newPayment.toStringAsFixed(2)} ج.م",
         'إجمالي المدفوع': record['paid'],
         'المتبقي': record['remaining'],
       }
     ]);
     
     setState(() {
       _view = 'confirmation';
     });
  }

  // --- UI HELPERS ---

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showPaymentDialog(String memberName) {
    _tripPaidController.clear();
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.white.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          title: Text("تسجيل دفعة لـ \"$memberName\"", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("الإجمالي للرحلة: ${_tripTotalCost!.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              TextField(
                controller: _tripPaidController,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "المبلغ المدفوع (الدفعة الحالية)",
                  labelStyle: TextStyle(color: Colors.cyan.shade200),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.cyan.shade400),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("إلغاء", style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () {
                final paidAmount = double.tryParse(_tripPaidController.text);
                if (paidAmount == null || paidAmount <= 0) {
                  // This is a local error, no need for a snackbar
                  return;
                }
                Navigator.of(context).pop();
                _processPayment(memberName, paidAmount);
              },
              child: const Text("تأكيد الدفعة"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // --- WIDGET BUILDER ---

  Widget _buildCurrentView() {
    switch (_view) {
      case 'main':
        return MainScreen(
          onModeSelect: _handleModeSelect,
          onViewChange: (view) => setState(() => _view = view),
        );
      case 'bulk_import':
        return BulkImportScreen(
          controller: _bulkImportController,
          onImport: _handleBulkImport,
          onBack: () => setState(() => _view = 'main'),
        );
      case 'select_trip':
        return SelectTripScreen(
          events: _events,
          onTripSelected: (trip) {
            setState(() {
              _eventName = trip.name;
              _tripTotalCost = trip.totalCost;
              _view = 'scanner';
            });
          },
          onCreateNew: () => _showCreateTripDialog(),
          onBack: () => setState(() => _view = 'main'),
        );
      case 'scanner':
        return ScannerScreen(
          eventName: _eventName,
          mode: _mode,
          totalCost: _tripTotalCost,
          controller: _nameInputController,
          onScan: _handleScan,
          onBack: () => setState(() {
            _view = 'main';
            _nameInputController.clear();
          }),
        );
      case 'confirmation':
        return ConfirmationScreen(
          event: _selectedEvent!,
          onNewScan: () {
            setState(() {
              _nameInputController.clear();
              _view = 'scanner';
            });
          },
          onBack: () => setState(() => _view = 'main'),
        );
      // Add other views later (reports, etc.)
      default:
        return MainScreen(onModeSelect: _handleModeSelect, onViewChange: (view) => setState(() => _view = view));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1a237e), Color(0xFF0d47a1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "كنيسة الشهيدين أبي سيفين ودميانة",
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
              Expanded(
                child: Center(
                  child: _buildCurrentView(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Developed by ENG. Philopater Joseph",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Dialog for creating a new trip
  void _showCreateTripDialog() {
    _tripNameController.clear();
    _tripTotalController.clear();
    _eventExpiry = null;
    
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
           backgroundColor: Colors.white.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          title: const Text("إنشاء رحلة جديدة", textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _tripNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "اسم الرحلة",
                    labelStyle: TextStyle(color: Colors.cyan.shade200),
                     enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyan.shade400)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tripTotalController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "المبلغ الإجمالي (للفرد)",
                    labelStyle: TextStyle(color: Colors.cyan.shade200),
                     enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyan.shade400)),
                  ),
                ),
                const SizedBox(height: 16),
                // Date picker would be more complex, using a text field for now
                 TextField(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2101),
                    );
                    if (picked != null) {
                      setState(() {
                        _eventExpiry = picked.toIso8601String();
                      });
                    }
                  },
                  readOnly: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: _eventExpiry == null ? "تاريخ انتهاء التسجيل (اختياري)" : intl.DateFormat.yMMMMd('ar_EG').format(DateTime.parse(_eventExpiry!)),
                    labelStyle: TextStyle(color: Colors.cyan.shade200),
                     enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyan.shade400)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("إلغاء", style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              onPressed: () {
                final name = _tripNameController.text;
                final total = double.tryParse(_tripTotalController.text);
                if (name.isNotEmpty && total != null && total > 0) {
                  final newEvent = Event(name: name, type: 'trip', records: [], totalCost: total, expiryDate: _eventExpiry);
                  _saveEvents([..._events, newEvent]);
                  Navigator.of(context).pop();
                  setState(() {
                    _eventName = name;
                    _tripTotalCost = total;
                    _view = 'scanner';
                  });
                } else {
                  // Handle error
                }
              },
              child: const Text("إنشاء وبدء التسجيل"),
               style: ElevatedButton.styleFrom(
                backgroundColor: Colors.emerald,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- SCREENS ---

class MainScreen extends StatelessWidget {
  final Function(String) onModeSelect;
  final Function(String) onViewChange;
  const MainScreen({super.key, required this.onModeSelect, required this.onViewChange});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.network("https://i.postimg.cc/fRFpRBd2/wmremove-transformed.jpg", height: 120),
          const SizedBox(height: 16),
          const Text("نظام التسجيل", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 32),
          StyledButton(
            text: "تسجيل حضور اليوم",
            icon: Icons.check_circle_outline,
            onPressed: () => onModeSelect('attendance'),
            gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]),
          ),
          const SizedBox(height: 16),
          StyledButton(
            text: "تسجيل رحلة",
            icon: Icons.card_travel,
            onPressed: () => onModeSelect('trip'),
            gradient: const LinearGradient(colors: [Colors.emerald, Colors.green]),
          ),
          const SizedBox(height: 16),
          StyledButton(
            text: "استيراد الأعضاء",
            icon: Icons.group_add_outlined,
            onPressed: () => onViewChange('bulk_import'),
            gradient: const LinearGradient(colors: [Colors.indigo, Colors.purple]),
          ),
          // Add other buttons for reports later
        ],
      ),
    );
  }
}

class BulkImportScreen extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onImport;
  final VoidCallback onBack;
  const BulkImportScreen({super.key, required this.controller, required this.onImport, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("استيراد جماعي للأسماء", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          const Text("انسخ قائمة الأسماء من Excel أو Sheet والصقها هنا (كل اسم في سطر جديد).", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "مينا عادل\nبيتر سمير\nمريم جورج",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyan.shade400)),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: StyledButton(text: "رجوع", onPressed: onBack, gradient: LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade600]))),
              const SizedBox(width: 16),
              Expanded(child: StyledButton(text: "استيراد الآن", onPressed: onImport, gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]))),
            ],
          )
        ],
      ),
    );
  }
}

class SelectTripScreen extends StatelessWidget {
  final List<Event> events;
  final Function(Event) onTripSelected;
  final VoidCallback onCreateNew;
  final VoidCallback onBack;
  
  const SelectTripScreen({super.key, required this.events, required this.onTripSelected, required this.onCreateNew, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final activeTrips = events.where((e) => e.type == 'trip' && (e.expiryDate == null || DateTime.parse(e.expiryDate!).isAfter(today))).toList();

    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("تسجيل رحلة", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          const Text("اختر من الرحلات الحالية أو أنشئ رحلة جديدة", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200, // Constrain the height of the list
            child: activeTrips.isEmpty
                ? const Center(child: Text("لا توجد رحلات نشطة حالياً.", style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: activeTrips.length,
                    itemBuilder: (context, index) {
                      final trip = activeTrips[index];
                      return Card(
                        color: Colors.white.withOpacity(0.1),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          title: Text(trip.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text("التكلفة: ${trip.totalCost?.toStringAsFixed(2) ?? 'N/A'} ج.م", style: const TextStyle(color: Colors.white70)),
                          onTap: () => onTripSelected(trip),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 24),
          StyledButton(
            text: "+ إنشاء رحلة جديدة",
            onPressed: onCreateNew,
            gradient: const LinearGradient(colors: [Colors.emerald, Colors.green]),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onBack, child: const Text("العودة للقائمة الرئيسية", style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}

class ScannerScreen extends StatelessWidget {
  final String eventName;
  final String mode;
  final double? totalCost;
  final TextEditingController controller;
  final VoidCallback onScan;
  final VoidCallback onBack;

  const ScannerScreen({
    super.key,
    required this.eventName,
    required this.mode,
    this.totalCost,
    required this.controller,
    required this.onScan,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(eventName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          if (mode == 'trip') ...[
            const SizedBox(height: 8),
            Text("الإجمالي للرحلة: ${totalCost?.toStringAsFixed(2)} ج.م", style: const TextStyle(color: Colors.cyanAccent)),
          ],
          const SizedBox(height: 24),
          const Text("الرجاء إدخال اسم العضو", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20),
            decoration: InputDecoration(
              hintText: "الاسم من كود QR",
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.cyan.shade400)),
            ),
          ),
          const SizedBox(height: 24),
          StyledButton(text: "تأكيد وإرسال", onPressed: onScan, gradient: const LinearGradient(colors: [Colors.cyan, Colors.blue])),
          const SizedBox(height: 16),
          TextButton(onPressed: onBack, child: const Text("العودة للقائمة الرئيسية", style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}

class ConfirmationScreen extends StatelessWidget {
  final Event event;
  final VoidCallback onNewScan;
  final VoidCallback onBack;

  const ConfirmationScreen({super.key, required this.event, required this.onNewScan, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final details = event.records.first;
    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
          const SizedBox(height: 16),
          Text("تم التسجيل في \"${event.name}\" بنجاح!", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: details.entries.map<Widget>((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      children: [
                        TextSpan(text: "${entry.key}: ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                        TextSpan(text: entry.value.toString()),
                      ],
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: StyledButton(text: "القائمة الرئيسية", onPressed: onBack, gradient: LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade600]))),
              const SizedBox(width: 16),
              Expanded(child: StyledButton(text: "تسجيل شخص آخر", onPressed: onNewScan, gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]))),
            ],
          )
        ],
      ),
    );
  }
}

// --- WIDGETS ---

class StyledButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onPressed;
  final Gradient gradient;

  const StyledButton({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        primary: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 50),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
              ],
              Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
