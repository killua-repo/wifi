import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:process/process.dart';
import 'package:window_manager/window_manager.dart'; // استدعاء الحزمة الجديدة

class WifiProfile {
  final String name;
  final String password;
  WifiProfile({required this.name, required this.password});
}

// -- جديد: تعديل دالة main للتحكم في حجم النافذة --
Future<void> main() async {
  // التأكد من تهيئة كل شيء قبل تشغيل التطبيق
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة مدير النوافذ
  await windowManager.ensureInitialized();

  // إعدادات النافذة التي ستظهر
  WindowOptions windowOptions = const WindowOptions(
    size: Size(450, 750), // حجم يشبه الهاتف
    center: true,
    minimumSize: Size(400, 600),
    title: 'Windows WiFi Manager',
    titleBarStyle: TitleBarStyle.normal,
  );

  // انتظر حتى تصبح النافذة جاهزة ثم أظهرها
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const WifiManagerApp());
}

class WifiManagerApp extends StatelessWidget {
  const WifiManagerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Windows WiFi Manager',
      // -- جديد: تصميم داكن احترافي وثابت --
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal, // اللون الأساسي للتطبيق
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), // لون الخلفية
        cardColor: const Color(0xFF1E1E1E), // لون البطاقات
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E), // لون ثابت للشريط العلوي
          elevation: 0, // لا يوجد ظل تحت الشريط العلوي
          scrolledUnderElevation: 0, // لا يتغير اللون عند التمرير
        ),
      ),
      home: const WifiListScreen(),
    );
  }
}

class WifiListScreen extends StatefulWidget {
  const WifiListScreen({super.key});
  @override
  State<WifiListScreen> createState() => _WifiListScreenState();
}

class _WifiListScreenState extends State<WifiListScreen> {
  List<WifiProfile> _wifiProfiles = [];
  bool _isLoading = true;
  String _loadingMessage = 'Initializing...';
  final Set<String> _selectedProfiles = {};

  @override
  void initState() {
    super.initState();
    _loadAllWifiData();
  }
  
  Future<void> _loadAllWifiData() async {
    // ... (الكثير من الكود هنا لم يتغير)
    const processManager = LocalProcessManager();
    final profilesResult = await processManager.run(['netsh', 'wlan', 'show', 'profiles']);
    if (profilesResult.exitCode != 0) {
      setState(() {
        _loadingMessage = 'Error! Please run this app as an Administrator.';
        _isLoading = false;
      });
      return;
    }
    final output = profilesResult.stdout as String;
    final lines = output.split('\n');
    final profileNames = <String>[];
    for (final line in lines) {
      if (line.contains('All User Profile')) {
        profileNames.add(line.split(':')[1].trim());
      }
    }
    final loadedProfiles = <WifiProfile>[];
    for (int i = 0; i < profileNames.length; i++) {
      final name = profileNames[i];
      setState(() {
        // -- تغيير: رسالة تحميل أبسط وأفضل --
        _loadingMessage = 'Loading passwords... (${i + 1}/${profileNames.length})';
      });
      final passwordResult = await processManager.run(['netsh', 'wlan', 'show', 'profile', 'name="$name"', 'key=clear']);
      String password = 'Not found / Open network';
      if (passwordResult.exitCode == 0) {
        final passOutput = passwordResult.stdout as String;
        for (final passLine in passOutput.split('\n')) {
          if (passLine.contains('Key Content')) {
            password = passLine.split(':')[1].trim();
            break;
          }
        }
      } else {
        password = 'Permission Denied (Run as Admin)';
      }
      loadedProfiles.add(WifiProfile(name: name, password: password));
    }
    setState(() {
      _wifiProfiles = loadedProfiles;
      _isLoading = false;
    });
  }

  // --- باقي الدوال (الحذف والتحديد) لم تتغير ---
  void _autoSelectDirectProfiles() {
    setState(() {
      final pattern = RegExp(r'^DIRECT-.*?-SM-J415FN$');
      for (final profile in _wifiProfiles) {
        if (pattern.hasMatch(profile.name) && !_selectedProfiles.contains(profile.name)) {
          _selectedProfiles.add(profile.name);
        }
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedProfiles.length >= _wifiProfiles.length) {
        _selectedProfiles.clear();
      } else {
        _selectedProfiles.addAll(_wifiProfiles.map((p) => p.name));
      }
    });
  }

  Future<void> _deleteSelectedProfiles() async {
    final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Confirm Deletion'),
              content: Text('Are you sure you want to delete ${_selectedProfiles.length} profiles?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
              ],
            ));
    if (shouldDelete != true) return;
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Deleting profiles...';
    });
    const processManager = LocalProcessManager();
    for (final profileName in _selectedProfiles.toList()) {
      await processManager.run(['netsh', 'wlan', 'delete', 'profile', 'name="$profileName"']);
    }
    _selectedProfiles.clear();
    await _loadAllWifiData();
  }


  @override
  Widget build(BuildContext context) {
    final isAnythingSelected = _selectedProfiles.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(isAnythingSelected ? '${_selectedProfiles.length} Selected' : 'WiFi Passwords'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Auto-select "DIRECT" profiles',
            onPressed: _autoSelectDirectProfiles,
          ),
          IconButton(
            icon: Icon(_selectedProfiles.length >= _wifiProfiles.length ? Icons.deselect : Icons.select_all),
            tooltip: 'Select/Deselect All',
            onPressed: _toggleSelectAll,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_loadingMessage),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _wifiProfiles.length,
              itemBuilder: (context, index) {
                final profile = _wifiProfiles[index];
                final isSelected = _selectedProfiles.contains(profile.name);
                return Card(
                  elevation: isSelected ? 8 : 2, // ظل أكبر عند التحديد
                  color: isSelected ? Colors.teal.withOpacity(0.4) : Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? Colors.tealAccent : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.tealAccent)
                        : const Icon(Icons.wifi_lock_outlined),
                    title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: SelectableText(profile.password, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: 'Copy password',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: profile.password));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password Copied!'), duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedProfiles.remove(profile.name);
                        } else {
                          _selectedProfiles.add(profile.name);
                        }
                      });
                    },
                  ),
                );
              },
            ),
      floatingActionButton: isAnythingSelected
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Delete Selected'),
              backgroundColor: Colors.red.shade900,
              onPressed: _deleteSelectedProfiles,
            )
          : null,
    );
  }
}