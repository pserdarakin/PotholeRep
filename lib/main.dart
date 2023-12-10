import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tflite;
import 'package:image/image.dart' as img;
import 'LocationInputPage.dart';
import 'FirebaseHelper.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(PotholeApp());
}
class PotholeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pothole Classification App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PotholeHomePage(),
    );
  }
}

class PotholeHomePage extends StatefulWidget {
  @override
  _PotholeHomePageState createState() => _PotholeHomePageState();
}

class _PotholeHomePageState extends State<PotholeHomePage> {
  File? _image;
  String _resultText = 'Results will be displayed here.';
  final picker = ImagePicker();
  tflite.Interpreter? _interpreterClassification;
  tflite.Interpreter? _interpreterDetection;
  bool _isEligibleToSubmit = false;
  final firebaseHelper = FirebaseHelper();

  Future<void> handlePotholeDetection(String? severity, String? location) async {
    if (severity == null || (severity != 'High' && severity != 'Moderate')) {
      setState(() {
        _resultText = 'Pothole detected with severity: $severity \nPothole not severe enough to report.';
        _isEligibleToSubmit = false;
      });
      return;
    }

    setState(() {
      _resultText = "Pothole detected with severity: $severity";
      _isEligibleToSubmit = true;
    });

    // Add a 20-second delay here
    await Future.delayed(Duration(seconds: 6));

    // Navigate to Location Input Page
    final newLocation = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationInputPage(),
      ),
    );

    if (newLocation != null) {
      await firebaseHelper.submitReport(
        location: newLocation,
        severity: severity,
        resultText: _resultText,
      );
      setState(() {
        _resultText = "Report submitted successfully.";
      });
    }
  }


  void navigateToLocationInputPage() async {
    if (_image != null) {
      const location = 'Default Location';
      String severity = await classifyPothole(_image!, location.toString());
      setState(() {
        _resultText = "Classification complete. Severity: $severity";
      });
      handlePotholeDetection(severity, location);
    }
  }

  @override
  void initState() {
    super.initState();
    loadModel().then((value) {
      setState(() {});
    });
  }

  Future loadModel() async {
    try {
      _interpreterClassification = await tflite.Interpreter.fromAsset(
          'assets/pothole_classification_model.tflite');
      _interpreterDetection =
      await tflite.Interpreter.fromAsset('assets/pothole_detection_model.tflite');
    } catch (e) {
      print('Failed to load model.');
      print(e);
      _resultText = 'Failed to load model.';
    }
  }

  Future getImageFromCamera() async {
    getImage(ImageSource.camera);
  }

  Future getImageFromGallery() async {
    getImage(ImageSource.gallery);
  }

  Future getImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
    } else {
      print('No image selected.');
      setState(() {
        _resultText = 'No image selected.';
      });
    }
  }

  Future<bool> detectPothole(File image) async {
    var bytes = await image.readAsBytes();
    var decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      setState(() {
        _resultText = 'Error decoding image.';
      });
      return false;
    }

    // Resize the image to match the input size of the detection model
    var processedImage = img.copyResize(decodedImage, width: 224, height: 224);
    int inputSize = 1 * 224 * 224 * 3; // based on input tensor shape
    Uint8List inputList = Uint8List(inputSize);

    int index = 0;
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        int pixelValue = processedImage.getPixel(x, y);
        inputList[index] = (pixelValue >> 16) & 0xFF; // R
        inputList[index + 1] = (pixelValue >> 8) & 0xFF; // G
        inputList[index + 2] = pixelValue & 0xFF; // B
        index += 3;
      }
    }

    int outputSize = 1 * 2; // based on output tensor shape
    Uint8List outputList = Uint8List(outputSize);
    _interpreterDetection?.run(inputList, outputList);
    double potholeConfidence = outputList[0] / 255.0;
    double nonPotholeConfidence = outputList[1] / 255.0;
    bool isPothole = potholeConfidence > nonPotholeConfidence &&
        potholeConfidence > 0.5;
    return isPothole;
  }

  Future classifyPothole(File image, [String? location]) async {
    bool isPotholeDetected = await detectPothole(image);
    if (!isPotholeDetected) {
      setState(() {
        _resultText = 'No pothole detected.';
        _isEligibleToSubmit = false;
      });
      return;
    }

    var bytes = await image.readAsBytes();
    var decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      setState(() {
        _resultText = 'Error decoding image.';
      });
      return;
    }
    var processedImage = img.copyResize(decodedImage, width: 128, height: 128);

    // Create a buffer for the input image as a 4-dimensional list
    var inputList = List.generate(1, (i) =>
        List.generate(128, (j) =>
            List.generate(128, (k) => List.generate(3, (l) => 0.0))));
    for (int y = 0; y < 128; y++) {
      for (int x = 0; x < 128; x++) {
        int pixelValue = processedImage.getPixel(x, y);
        inputList[0][y][x][0] = ((pixelValue >> 16) & 0xFF) / 255.0;
        inputList[0][y][x][1] = ((pixelValue >> 8) & 0xFF) / 255.0;
        inputList[0][y][x][2] = (pixelValue & 0xFF) / 255.0;
      }
    }

    // Create the output buffer based on the output shape [1, 3]
    var outputList = List.generate(1, (i) => List.generate(3, (j) => 0.0));
    _interpreterClassification?.run(inputList, outputList);

    var outputBuffer = Float32List.fromList(
        outputList.expand((i) => i).toList());

    var severity = classifyOutput(outputBuffer);
    handlePotholeDetection(severity, location);
  }

  String classifyOutput(Float32List output) {
    var labels = ['High', 'Low', 'Moderate'];
    var maxValue = output[0];
    var maxIndex = 0;

    for (int i = 1; i < output.length; i++) {
      if (output[i] > maxValue) {
        maxValue = output[i];
        maxIndex = i;
      }
    }
    return labels[maxIndex];
  }

  @override
  void dispose() {
    _interpreterClassification?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pothole Report'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
          Card(
          elevation: 5,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera),
                    onPressed: getImageFromCamera,
                    label: const Text('Capture'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    onPressed: getImageFromGallery,
                    label: const Text('Upload'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.done),
                    onPressed: _image != null ? () => navigateToLocationInputPage() : null,
                    label: const Text('Classify'),
                    ),
                  ],
                ),
              ),
            ),
          ),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                elevation: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: _image == null
                        ? const Text('Image will be displayed here.',
                      textAlign: TextAlign.center,)
                        : Image.file(_image!),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_resultText, textAlign: TextAlign.center,),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
