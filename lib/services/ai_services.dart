// lib/services/ai_services.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // 🔥 Your Python server URL
  // For Android Emulator, use: http://10.0.2.2:5000
  // For iOS Simulator or desktop, use: http://127.0.0.1:5000
  // For real device, use: http://YOUR_COMPUTER_IP:5000
  static const String _baseUrl = 'http://127.0.0.1:5000';

  /// Converts natural language query to structured JSON filters using Groq AI
  ///
  /// Example:
  /// ```dart
  /// final result = await AiService.parseQuery(
  ///   "Need chicken meals for 50 people near Anna Nagar urgently"
  /// );
  /// print(result['filters']['foodName']); // "chicken"
  /// print(result['filters']['quantityPeople']); // 50
  /// ```
  static Future<Map<String, dynamic>> parseQuery(String userQuery) async {
    // Validation
    if (userQuery.trim().isEmpty) {
      return {
        "filters": {
          "foodName": null,
          "foodType": null,
          "quantityPeople": null,
          "locationHint": null,
          "urgency": null
        }
      };
    }

    try {
      print('📤 Sending query to AI: $userQuery');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/ai-search'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'query': userQuery,
            }),
          )
          .timeout(const Duration(seconds: 15));

      print('📥 AI Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        print('✅ AI Parsed Filters: ${data['filters']}');

        // Normalize the response to ensure all expected fields exist
        final filters = data['filters'] as Map<String, dynamic>? ?? {};

        // Normalize foodType: convert non_veg to non-veg for Firestore compatibility
        String? foodType = filters['foodType'];
        if (foodType != null) {
          foodType = foodType.replaceAll('_', '-');
        }

        return {
          "filters": {
            "foodName": filters['foodName'],
            "foodType": foodType,
            "quantityPeople": filters['quantityPeople'],
            "locationHint": filters['locationHint'],
            "urgency": filters['urgency'],
          }
        };
      } else {
        throw Exception(
            'Server Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ AI Service Error: $e');

      // Fallback to simple parser if server is unreachable
      return _simpleParser(userQuery);
    }
  }

  /// Check if the Python server is running
  static Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Server Status: ${data['status']}');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Server not reachable: $e');
      return false;
    }
  }

  /// Simple keyword-based fallback parser (used when server is unavailable)
  static Map<String, dynamic> _simpleParser(String query) {
    print('⚠️ Using fallback parser');

    final lowerQuery = query.toLowerCase();

    // Extract food type
    String? foodType;
    if (lowerQuery.contains('veg') && !lowerQuery.contains('non')) {
      foodType = 'veg';
    } else if (lowerQuery.contains('non-veg') ||
        lowerQuery.contains('non veg') ||
        lowerQuery.contains('nonveg') ||
        lowerQuery.contains('chicken') ||
        lowerQuery.contains('mutton') ||
        lowerQuery.contains('fish')) {
      foodType = 'non_veg';
    }

    // Extract food name
    String? foodName;
    final foodKeywords = [
      'rice',
      'chicken',
      'idli',
      'dosa',
      'biryani',
      'meals',
      'curry',
      'dal',
      'chapati',
      'roti'
    ];
    for (var food in foodKeywords) {
      if (lowerQuery.contains(food)) {
        foodName = food;
        break;
      }
    }

    // Extract quantity
    int? quantity;
    final numberMatch = RegExp(r'\d+').firstMatch(query);
    if (numberMatch != null) {
      quantity = int.tryParse(numberMatch.group(0)!);
    }

    // Extract urgency
    String? urgency;
    if (lowerQuery.contains('urgent') ||
        lowerQuery.contains('asap') ||
        lowerQuery.contains('immediately')) {
      urgency = 'urgent';
    } else {
      urgency = 'normal';
    }

    // Extract location
    String? location;
    final nearMatch = RegExp(
            r'(?:near|at|in|around)\s+([a-zA-Z\s]+?)(?:\s+for|\s+urgently|$)',
            caseSensitive: false)
        .firstMatch(query);
    if (nearMatch != null) {
      location = nearMatch.group(1)?.trim();
    }

    return {
      "filters": {
        "foodName": foodName,
        "foodType": foodType,
        "quantityPeople": quantity,
        "locationHint": location,
        "urgency": urgency
      }
    };
  }
}
