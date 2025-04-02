import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonDecode
import 'package:dart_appwrite/dart_appwrite.dart';

// Uses context.res.json() - CORRECT for Dart 3.x runtimes
Future<dynamic> main(final context) async {
  // --- Initialize Client ---
   final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
   final String apiEndpoint = Platform.environment['APPWRITE_ENDPOINT'] ?? ''; // Use standard endpoint var
   final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

   if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
      context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
      return context.res.json({ // Use json()
         'success': false,
         'error': 'Function is not configured correctly.'
      }, statusCode: 500);
   }

   final client = Client()
      .setEndpoint(apiEndpoint)
      .setProject(projectId)
      .setKey(apiKey)
      .setSelfSigned(status: true); // Keep if needed for self-hosting

   final users = Users(client);

  // --- Parse Request Body ---
   Map<String, dynamic> body;
   String? userId;
   String? action;
   String requestBodyRaw = context.req.bodyRaw ?? '';

   try {
      context.log('Raw request body received: $requestBodyRaw');
      if (requestBodyRaw.isEmpty) {
         context.log('Request body is empty.');
         return context.res.json( // Use json()
            {'success': false, 'error': 'Request body is empty'},
            statusCode: 400);
      }
      // ... rest of your parsing logic ...
      body = jsonDecode(requestBodyRaw);
      userId = body['userId'] as String?; // Add safety checks if needed
      action = body['action'] as String?;

      if (userId == null || userId.isEmpty) {
         return context.res.json({'success': false, 'error': 'Missing userId'}, statusCode: 400); // Use json()
      }
      if (action == null || action != 'makeAdmin') {
         return context.res.json({'success': false, 'error': 'Invalid action'}, statusCode: 400); // Use json()
      }

   } catch (e, stackTrace) {
      context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
      return context.res.json( // Use json()
            {'success': false, 'error': 'Invalid JSON format.', 'details': e.toString()},
            statusCode: 400);
   }

   // --- Update User Labels ---
   try {
       // ... your user update logic ...
       final user = await users.get(userId: userId);
       // ... logic to check/add label ...
       await users.updateLabels(userId: userId, labels: updatedLabelsList);

       return context.res.json({ // Use json() for success
           'success': true,
           'message': 'Admin label added successfully.',
           'userId': userId,
           'updatedLabels': updatedLabelsList,
       });

   } on AppwriteException catch (e) {
        context.error('Appwrite Error: [${e.code}] ${e.message}');
        // ... error handling ...
        return context.res.json({ // Use json() for Appwrite errors
            'success': false,
            'error': errorMessage, // Your determined error message
            'details': e.message,
            'code': e.code
        }, statusCode: statusCode); // Your determined status code

   } catch (e, stackTrace) {
      context.error('Generic unexpected error: ${e.toString()}\nStackTrace: ${stackTrace}');
      return context.res.json({ // Use json() for generic errors
         'success': false,
         'error': 'An unexpected internal server error occurred.',
         'details': e.toString()
      }, statusCode: 500);
   }
}
