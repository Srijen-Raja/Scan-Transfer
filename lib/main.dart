import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.deepPurple,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.deepPurple.shade50,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.deepPurple.shade50,
        elevation: 0,
      ),
    ),
    home: HomeScreen(),
  ));
}

final List<String> _adjectives = [
  "Golden", "Silver", "Crimson", "Swift", "Bright", "Mighty", "Royal",
  "Electric", "Neon", "Frozen", "Cosmic", "Lunar", "Solar", "Vivid",
  "Wild", "Quiet", "Dancing", "Flying", "Hidden", "Ancient", "Primal",
  "Crystal", "Mystic", "Turbo", "Velvet", "Frosty", "Zesty", "Magic"
];

final List<String> _fruits = [
  "Mango", "Apple", "Banana", "Kiwi", "Orange", "Cherry", "Grape", "Peach",
  "Papaya", "Melon", "Berry", "Dragonfruit", "Lychee", "Guava", "Plum",
  "Apricot", "Fig", "Pear", "Coconut", "Avocado", "Lime", "Lemon",
  "Pineapple", "Durian", "Passionfruit", "Jackfruit", "Starfruit", "Olive"
];

String _generateUniqueName() {
  final random = Random();
  String adj = _adjectives[random.nextInt(_adjectives.length)];
  String fruit = _fruits[random.nextInt(_fruits.length)];
  int number = random.nextInt(99) + 1; // Number between 1 and 99
  return "$adj $fruit #$number";
}

Future<void> _deleteAllImages(BuildContext context) async {
  bool confirm = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Delete All Images?"),
      content: const Text("This will remove all images from Cloud. This action cannot be undone."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete Everything", style: TextStyle(color: Colors.red))),
      ],
    ),
  ) ?? false;

  if (confirm) {
    try {
      final collection = FirebaseFirestore.instance.collection('images');
      final snapshots = await collection.get();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshots.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All Cloud Data Deleted"), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }
}

// --- UI Components ---
class ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const ActionCard({super.key, required this.title, required this.icon, required this.color, required this.onTap});



  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        height: 160,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// --- Home Screen ---
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade50],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Welcome back,", style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                    const Text("Srijen", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ActionCard(
                    title: "Send",
                    icon: Icons.send_rounded,
                    color: Colors.deepPurple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SendScreen())),
                  ),
                  ActionCard(
                    title: "Receive",
                    icon: Icons.call_received_rounded,
                    color: Colors.blueAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiveScreen())),
                  ),
                ],
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Send Screen ---
class SendScreen extends StatefulWidget {
  @override
  _SendScreenState createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {

  double _targetSizeKb = 500.0;
  bool _isCompressing = false;

  final DocumentScanner _documentScanner = DocumentScanner(
    options: DocumentScannerOptions(mode: ScannerMode.full, isGalleryImport: true),
  );
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSavedSize();
  }


  Future<void> _loadSavedSize() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _targetSizeKb = prefs.getDouble('user_size_setting') ?? 500.0;
    });
  }

  Future<void> _updateSize(double newValue) async {
    setState(() => _targetSizeKb = newValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_size_setting', newValue);
  }


  Future<void> _uploadImage(Uint8List bytes) async {
    setState(() => _isCompressing = true);

    Uint8List compressedBytes = bytes;
    double targetSizeBytes = _targetSizeKb * 1024;
    int finalQuality = 100;


    for (int q = 100; q > 5; q -= 15) {
      compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minHeight: 1920,
        minWidth: 1080,
        quality: q,
      );

      finalQuality = q;
      if (compressedBytes.lengthInBytes <= targetSizeBytes) break;
    }

    String base64Image = base64Encode(compressedBytes);
    String uniqueName = _generateUniqueName();
    await FirebaseFirestore.instance.collection('images').add({
      'data': base64Image,
      'timestamp': FieldValue.serverTimestamp(),
      'fruitName': uniqueName,
    });

    if (mounted) {
      setState(() => _isCompressing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Uploaded Image of Size ${(compressedBytes.lengthInBytes / 1024).toStringAsFixed(1)}KB (Q: $finalQuality)"),
          backgroundColor: Colors.deepPurple,
        ),
      );
    }
  }


  Future<void> _pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      Uint8List bytes = await image.readAsBytes();
      await _uploadImage(bytes);
    }
  }

  Future<void> _scanDocument() async {
    try {
      final result = await _documentScanner.scanDocument();
      final images = result.images;
      if (images != null && images.isNotEmpty) {
        Uint8List bytes = await File(images.first).readAsBytes();
        await _uploadImage(bytes);
      }
    } catch (e) {
      debugPrint("Scanning Error: $e");
    }
  }

  @override
  void dispose() {
    _documentScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Send Image"), centerTitle: true),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(child: ActionCard(title: "Gallery", icon: Icons.photo_library_rounded, color: Colors.indigo, onTap: _pickFromGallery)),
                        const SizedBox(width: 20),
                        Expanded(child: ActionCard(title: "Scan", icon: Icons.document_scanner_rounded, color: Colors.deepPurple, onTap: _scanDocument)),
                      ],
                    ),
                  ),
                ),
              ),


              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Target Max Size", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("${_targetSizeKb.toInt()} KB", style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Slider(
                      value: _targetSizeKb,
                      min: 100,
                      max: 1000,
                      divisions: 9,
                      activeColor: Colors.deepPurple,
                      onChanged: (value) => setState(() => _targetSizeKb = value),
                      onChangeEnd: (value) => _updateSize(value),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_isCompressing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
// --- Receive Screen ---
class ReceiveScreen extends StatefulWidget {
  @override
  _ReceiveScreenState createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  Set<String> _downloadedIds = {};

  @override
  void initState() {
    super.initState();
    _loadDownloadHistory();
  }


  Future<void> _saveToCustomFolder(Uint8List bytes, String fileName) async {
    try {
      Directory? baseDir = await getExternalStorageDirectory();
      String newPath = "/storage/emulated/0/Pictures/Scans";
      Directory customDir = Directory(newPath);
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      File file = File("${customDir.path}/$fileName.jpg");
      await file.writeAsBytes(bytes);
      // 5. Scan the new file so it shows up in the Photos app
      await MediaScanner.loadMedia(path: file.path);

    } catch (e) {
      debugPrint("Error saving to folder: $e");
    }
  }

  Future<void> _loadDownloadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? history = prefs.getStringList('downloaded_images');
    if (history != null) setState(() => _downloadedIds = history.toSet());
  }

  Future<void> _saveToHistory(String docId) async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds.add(docId);
    await prefs.setStringList('downloaded_images', _downloadedIds.toList());
    setState(() {});
  }

  Future<void> _autoDownload(String docId, String base64Data) async {
    if (_downloadedIds.contains(docId) || base64Data.isEmpty) return;

    try {
      Uint8List bytes = base64Decode(base64Data);
      String fileName = "Scan_${docId.substring(0, 5)}_${DateTime.now().millisecondsSinceEpoch}";
      await _saveToCustomFolder(bytes, fileName);
      await _saveToHistory(docId);
    } catch (e) {
      debugPrint("Download error: $e");
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Receiving Hub"),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () => _deleteAllImages(context)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('images').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;

          if (docs.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              for (var doc in docs) {
                if (!_downloadedIds.contains(doc.id)) {
                  var data = doc.data() as Map<String, dynamic>?;
                  if (data != null && data.containsKey('data')) {
                    _autoDownload(doc.id, data['data']);
                  }
                }
              }
            });
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var doc = docs[index];
              var data = doc.data() as Map<String, dynamic>;
              String? base64String = data['data'];
              bool isSaved = _downloadedIds.contains(doc.id);
              String fruitName = data['fruitName'] ?? "Image #${doc.id.substring(0, 4)}";
              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    isSaved ? Icons.check_circle : Icons.sync,
                    color: isSaved ? Colors.green : Colors.blue,
                  ),
                  title: Text(fruitName),
                  subtitle: Text(isSaved ? "Saved to Gallery" : "Syncing..."),

                  trailing: (base64String != null && base64String.isNotEmpty)
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(base64String),
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  )
                      : const Icon(Icons.image_not_supported),
                ),
              );
            },
          );
        },
      ),
    );
  }
}