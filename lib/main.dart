import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() {
  runApp(const MaterialApp(home: ChatScreen()));
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  Llama? _llama;
  String _response = "Model not loaded";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupLlama();
  }

  Future<void> _setupLlama() async {
    setState(() => _response = "Initializing model...");

    try {
      // 1. Point to the shared library
      if (Platform.isAndroid) {
        // On Android, if libllama.so is in jniLibs, it loads automatically.
        // But sometimes you need to explicitly open it depending on the binding version.
        try {
          // 1. Try loading the dependency first
          DynamicLibrary.open("libc++_shared.so");
        } catch (e) {
          if (kDebugMode) {
            print("Warning: Could not load libc++_shared.so: $e");
          }
        }
        Llama.libraryPath = "libllama.so";
      } else if (Platform.isIOS || Platform.isMacOS) {
        Llama.libraryPath = "libllama.dylib";
      }

      // 2. Move model from Assets to Device Storage
      final directory = await getApplicationDocumentsDirectory();
      final modelPath = '${directory.path}/model.gguf';
      final file = File(modelPath);

      if (!await file.exists()) {
        setState(
          () => _response = "Copying model from assets (this takes time)...",
        );
        final byteData = await rootBundle.load(
          'assets/models/Qwen3-0.6B-Q4_K_M.gguf',
        );
        await file.writeAsBytes(byteData.buffer.asUint8List());
      }

      // 3. Initialize Llama
      // Adjust parameters based on your device's RAM
      final modelParams = ModelParams();
      final contextParams = ContextParams();
      contextParams.nCtx = 512; // Context window size (lower = less RAM)

      _llama = Llama(
        modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
      );

      setState(() => _response = "Ready! Ask me something.");
    } catch (e) {
      setState(() => _response = "Error: $e");
    }
  }

  Future<void> _generateText() async {
    if (_llama == null || _controller.text.isEmpty) return;

    final prompt = _controller.text;
    setState(() {
      _response = "";
      _isLoading = true;
      _controller.clear();
    });

    // Run in a loop, calling getNext() until done
    try {
      _llama!.setPrompt(prompt);

      // Loop through tokens until generation is complete
      bool isDone = false;
      while (!isDone) {
        final (token, done) = _llama!.getNext();
        isDone = done;

        if (token.isNotEmpty) {
          setState(() {
            _response += token;
          });
        }
      }
    } catch (e) {
      setState(() => _response += "\n[Error generating response]");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _llama?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Local AI Chat")),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(_response, style: const TextStyle(fontSize: 16)),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Enter prompt...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isLoading ? null : _generateText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
