import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Import for jsonDecode
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function updates a user's labels to add 'admin'.
// It expects a JSON request body containing: {"userId": "TARGET_USER_ID"}
Future<dynamic> main(final context) async {
  // --- 1. Initialize Appwrite Client ---
  // Ensure you have set APPWRITE_API_KEY in your function's environment variables
  // This key needs users.read and users.write permissions.
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    context.error('Security Error: APPWRITE_API_KEY environment variable is not set.');
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly. Missing API Key.'
    }, statusCode: 500);
  }

  final client = Client()
    .setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '')
    .setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '')
    .setKey(apiKey); // Use the secure API key from environment variables

  final users = Users(client);

  // --- 2. Parse Request Body for userId ---
  Map<String, dynamic> body;
  String? userId;

  try {
    // Ensure body is not empty before decoding
    if (context.req.bodyRaw == null || context.req.bodyRaw.isEmpty) {
       return context.res.json({'success': false, 'error': 'Request body is empty'}, statusCode: 400);
    }
    body = jsonDecode(context.req.bodyRaw);
    userId = body['userId'] as String?; // Safely cast and handle null

    if (userId == null || userId.isEmpty) {
      return context.res.json({
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }
  } catch (e) {
    context.error('Failed to parse request body: $e');
    return context.res.json({
      'success': false,
      'error': 'Invalid JSON format in request body.'
    }, statusCode: 400);
  }

  context.log('Attempting to add "admin" label to user: $userId');

  // --- 3. Get User, Modify Labels, Update User ---
  try {
    // Get the user's current details to fetch existing labels
    final user = await users.get(userId: userId);
    final List<String> currentLabels = user.labels;

    // Use a Set to easily add the new label and avoid duplicates
    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
       context.log('User $userId already has the "admin" label.');
       return context.res.json({
         'success': true, // Still success, just no change needed
         'message': 'User already has the admin label.',
         'userId': userId,
         'labels': currentLabels, // Return current labels
       });
    }

    // Add the 'admin' label
    newLabelsSet.add('admin');

    // Convert back to List<String> for the API call
    final List<String> updatedLabelsList = newLabelsSet.toList();

    // Update the user's labels
    await users.updateLabels(userId: userId, labels: updatedLabelsList);

    context.log('Successfully added "admin" label for user: $userId');
    return context.res.json({
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    });

  } on AppwriteException catch (e) {
    // Handle specific Appwrite errors
    context.error('Appwrite Error updating labels for user $userId: [${e.code}] ${e.message}');
    int statusCode = 500; // Default internal server error
    String errorMessage = 'Failed to update user labels.';

    if (e.code == 404) { // User not found
      statusCode = 404;
      errorMessage = 'User not found with ID: $userId';
    } else if (e.code == 400) { // Bad request (e.g., invalid label format, though unlikely here)
       statusCode = 400;
       errorMessage = 'Bad request during label update: ${e.message}';
    } else if (e.code == 401 || e.code == 403) { // Unauthorized/Forbidden (API key issue)
        statusCode = 500; // Return 500 to hide internal permission details
        errorMessage = 'Function configuration error (permissions).';
        context.error('API Key might lack permissions (users.read/users.write) or is invalid.');
    }

    return context.res.json({
      'success': false,
      'error': errorMessage,
      'details': e.message, // Optionally include Appwrite message for debugging
    }, statusCode: statusCode);

  } catch (e) {
    // Handle other unexpected errors
    context.error('Generic Error updating labels for user $userId: ${e.toString()}');
    return context.res.json({
      'success': false,
      'error': 'An unexpected server error occurred.'
    }, statusCode: 500);
  }
}
