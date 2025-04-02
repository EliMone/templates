import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Needed for jsonDecode
import 'package:dart_appwrite/dart_appwrite.dart';

Future<dynamic> main(final context) async {
  // --- Initialize Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  if (apiKey.isEmpty || apiEndpoint.isEmpty || projectId.isEmpty) {
    context.error('Configuration Error: Missing API Key, Endpoint, or Project ID.');
    return context.res.json({
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
      return context.res.json(
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }
    body = jsonDecode(requestBodyRaw);
    context.log('Parsed request body: $body');

    userId = body['userId'] as String?; // Add safety checks if needed
    action = body['action'] as String?;

    if (userId == null || userId.isEmpty) {
      return context.res.json({'success': false, 'error': 'Missing or empty "userId"'}, statusCode: 400);
    }
    if (action == null || action != 'makeAdmin') {
      return context.res.json({'success': false, 'error': 'Missing or invalid action. Supported: "makeAdmin"'}, statusCode: 400);
    }

  } catch (e, stackTrace) {
    context.error('Failed to parse request body: $e\nStackTrace: $stackTrace');
    return context.res.json(
          {'success': false, 'error': 'Invalid JSON format.', 'details': e.toString()},
          statusCode: 400);
  }

  // --- Update User Labels ---
  try {
    context.log('Fetching user details for $userId...');
    final user = await users.get(userId: userId);
    context.log('Successfully fetched user details for $userId.');

    final List<String> currentLabels = user.labels; // Assuming modern SDK
    context.log('Current labels: $currentLabels');

    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      return context.res.json({
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      });
    }

    // *** FIX: Define updatedLabelsList ***
    newLabelsSet.add('admin');
    final List<String> updatedLabelsList = newLabelsSet.toList(); // <-- ADD THIS LINE BACK
    context.log('Prepared updated labels list: $updatedLabelsList');

    context.log('Attempting users.updateLabels for $userId...');
    // *** Use the defined variable ***
    await users.updateLabels(userId: userId, labels: updatedLabelsList); // <-- This line is now valid
    context.log('users.updateLabels call completed successfully for $userId.');


    return context.res.json({
        'success': true,
        'message': 'Admin label added successfully.',
        'userId': userId,
        // *** Use the defined variable ***
        'updatedLabels': updatedLabelsList, // <-- This line is now valid
    });

  } on AppwriteException catch (e) {
    context.error('Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');

    // *** FIX: Define statusCode and errorMessage ***
    int statusCode = 500; // <-- ADD Default status code
    String errorMessage = 'Failed to update user labels due to Appwrite error.'; // <-- ADD Default error message

    if (e.code == 404) { // User not found
        statusCode = 404;
        errorMessage = 'User not found with ID: $userId';
    } else if (e.code == 401) { // Permissions issue?
        statusCode = 401; // Or 403 Forbidden depending on context
        errorMessage = 'API Key lacks permission to update user labels.';
    } else if (e.code == 400) { // Bad request (e.g., invalid label format)
        statusCode = 400;
        errorMessage = 'Bad request updating labels (check label format/content).';
    }
    // Add more specific Appwrite error code handling if needed

    final errorResponse = {
        'success': false,
        // *** Use the defined variable ***
        'error': errorMessage, // <-- This line is now valid
        'details': e.message,
        'code': e.code
    };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...');
    // *** Use the defined variable ***
    return context.res.json(errorResponse, statusCode: statusCode); // <-- This line is now valid

  } catch (e, stackTrace) {
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = {
      'success': false,
      'error': 'An unexpected internal server error occurred.',
      'details': e.toString()
    };
    context.log('Preparing to send generic error response...');
    return context.res.json(errorResponse, statusCode: 500);
  }
}
