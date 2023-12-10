import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseHelper {

  final CollectionReference reportCollection =
  FirebaseFirestore.instance.collection('reports');

  Future<DocumentReference<Object?>> submitReport({
    required String location,
    required String severity,
    required String resultText,
  }) async {
    return await reportCollection.add({
      'location': location,
      'severity': severity,
      'resultText': resultText,
      'timestamp': Timestamp.now(),
    });
  }
}
