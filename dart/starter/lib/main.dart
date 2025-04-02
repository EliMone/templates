import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function updates a user's labels to add 'admin'.
// It expects a JSON request body containing: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- 1. Initialize Appwrite Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    context.error(
        'Security Error: APPWRITE_API_KEY environment variable is not set.');
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly. Missing API Key.'
    }, statusCode: 500);
  }

  final client = Client()
      .setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '')
      .setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '')
      .setKey(apiKey);

  final users = Users(client);

  // --- 2. Parse Request Body for userId and action ---
  Map<String, dynamic> body;
  String? userId;
  String? action;

  try {
    // Ensure body is not empty before decoding
    if (context.req.bodyRaw == null || context.req.bodyRaw.isEmpty) {
      return context.res.json(
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }
    body = jsonDecode(context.req.bodyRaw);
    userId = body['userId'] as String?;
    action = body['action'] as String?;

    if (userId == null || userId.isEmpty) {
      return context.res.json({
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }

    // Validate the action
    if (action != null && action != 'makeAdmin') {
      return context.res.json({
        'success': false,
        'error': 'Invalid action. Supported action is "makeAdmin".'
      }, statusCode: 400);
    }
  } catch (e) {
    context.error('Failed to parse request body: $e');
    return context.res.json(
        {'success': false, 'error': 'Invalid JSON format in request body.'},
        statusCode: 400);
  }

  context.log('Attempting to add "admin" label to user: $userId');

  // --- 3. Get User, Modify Labels, Update User ---
  try {
    // Get the user's current details to fetch existing labels
    final user = await users.get(userId: userId);
    final List<String> currentLabels = user.labels;

    // Debug: Print total number of users for monitoring purpose
    try {
      final usersList = await users.list();
      context.log('Total users: ${usersList.total}');
    } catch (e) {
      // Just log, don't stop execution
      context.log('Unable to get total users count: $e');
    }

    // Use a Set to easily add the new label and avoid duplicates
    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      // Always use the response variable - ensures it's properly returned
      final response = {
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels,
      };
      return context.res.json(response);
    }

    // Add the 'admin' label
    newLabelsSet.add('admin');

    // Convert back to List<String> for the API call
    final List<String> updatedLabelsList = newLabelsSet.toList();

    // Update the user's labels
    await users.updateLabels(userId: userId, labels: updatedLabelsList);

    context.log('Successfully added "admin" label for user: $userId');
    // Always use the response variable - ensures it's properly returned
    final response = {
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    };
    return context.res.json(response);
  } on AppwriteException catch (e) {
    // Handle specific Appwrite errors
    context.error(
        'Appwrite Error updating labels for user $userId: [${e.code}] ${e.message}');
    int statusCode = 500; // Default internal server error
    String errorMessage = 'Failed to update user labels.';

    if (e.code == 404) {
      // User not found
      statusCode = 404;
      errorMessage = 'User not found with ID: $userId';
    } else if (e.code == 400) {
      // Bad request
      statusCode = 400;
      errorMessage = 'Bad request during label update: ${e.message}';
    } else if (e.code == 401 || e.code == 403) {
      // Unauthorized/Forbidden
      statusCode = 500; // Return 500 to hide internal permission details
      errorMessage = 'Function configuration error (permissions).';
      context.error(
          'API Key might lack permissions (users.read/users.write) or is invalid.');
    }

    // Always use the errorResponse variable - ensures it's properly returned
    final errorResponse = {
      'success': false,
      'error': errorMessage,
      'details': e.message,
      'code': e.code,
    };
    return context.res.json(errorResponse, statusCode: statusCode);
  } catch (e) {
    // Handle other unexpected errors
    context.error(
        'Generic Error updating labels for user $userId: ${e.toString()}');
    // Always use the errorResponse variable - ensures it's properly returned
    final errorResponse = {
      'success': false,
      'error': 'An unexpected server error occurred.',
      'details': e.toString(),
    };
    return context.res.json(errorResponse, statusCode: 500);
  }
}
