import 'package:flutter/material.dart';

class LocationInputPage extends StatelessWidget {
  final TextEditingController locationController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('REPORT')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: locationController,
              decoration: InputDecoration(
                labelText: 'Enter the location of the pothole (POST CODE,CITY)',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, locationController.text);
              },
              child: Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
