import 'dart:convert';
import 'package:http/http.dart' as http;

class EditCodeService {
  final String baseUrl;

  EditCodeService({this.baseUrl = "http://localhost:5000"}); // or your deployed backend URL

  Future<String?> editCode({
    required String fileContent,
    required String instruction,
  }) async {
    final url = Uri.parse('$baseUrl/edit-code');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileContent': fileContent,
        'instruction': instruction,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['updatedCode'] as String?;
    } else {
      return null;
    }
  }
}