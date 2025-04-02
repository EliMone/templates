import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function updates a user's labels to add 'admin'.
// It expects a JSON request body containing: {"userId": "TARGET_USER_ID", "action": "makeAdmin"}
Future<dynamic> main(final context) async {
  // --- 1. Initialize Appwrite Client ---
  final String apiKey = Platform.environment['APPWRITE_API_KEY'] ?? '';
  final String apiEndpoint = Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '';
  final String projectId = Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '';

  // Validate essential environment variables
  if (apiKey.isEmpty) {
    context.error('Security Error: APPWRITE_API_KEY environment variable is not set.');
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly. Missing API Key.'
    }, statusCode: 500);
  }
  if (apiEndpoint.isEmpty) {
    context.error('Configuration Error: APPWRITE_FUNCTION_API_ENDPOINT environment variable is not set.');
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly. Missing API Endpoint.'
    }, statusCode: 500);
  }
   if (projectId.isEmpty) {
    context.error('Configuration Error: APPWRITE_FUNCTION_PROJECT_ID environment variable is not set.');
    return context.res.json({
      'success': false,
      'error': 'Function is not configured correctly. Missing Project ID.'
    }, statusCode: 500);
  }

  final client = Client()
      .setEndpoint(apiEndpoint)
      .setProject(projectId)
      .setKey(apiKey);

  final users = Users(client);

  // --- 2. Parse Request Body for userId and action ---
  Map<String, dynamic> body;
  String? userId;
  String? action;

  try {
    // Ensure body is not empty before decoding
    if (context.req.bodyRaw == null || context.req.bodyRaw.isEmpty) {
       context.log('Request body is empty.'); // Log before returning
      return context.res.json(
          {'success': false, 'error': 'Request body is empty'},
          statusCode: 400);
    }
    body = jsonDecode(context.req.bodyRaw);
    userId = body['userId'] as String?;
    action = body['action'] as String?; // Keep action parsing for potential future use/validation

    if (userId == null || userId.isEmpty) {
       context.log('Missing or empty "userId" in request body.'); // Log before returning
      return context.res.json({
        'success': false,
        'error': 'Missing or empty "userId" in request body.'
      }, statusCode: 400);
    }

    // Optional: Keep action validation if you might add more actions later
    if (action != null && action != 'makeAdmin') {
       context.log('Invalid action received: $action'); // Log before returning
      return context.res.json({
        'success': false,
        'error': 'Invalid action. Supported action is "makeAdmin".'
      }, statusCode: 400);
    }
     if (action == null) {
        // If you *require* the action field even if it's always 'makeAdmin'
        context.log('Missing "action" field in request body.'); // Log before returning
        return context.res.json({
          'success': false,
          'error': 'Missing "action" field in request body.'
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
     context.log('Fetching user details for $userId...');
    final user = await users.get(userId: userId);
    context.log('Successfully fetched user details for $userId.');
    final List<String> currentLabels = List<String>.from(user.labels); // Ensure it's mutable if needed, and correct type

    // Debug: Print total number of users (keep for verification)
    try {
      final usersList = await users.list();
      context.log('Total users check: ${usersList.total}');
    } catch (e) {
      context.log('Info: Unable to get total users count during process: $e');
    }

    // Use a Set to easily add the new label and avoid duplicates
    final Set<String> newLabelsSet = Set<String>.from(currentLabels);
    bool alreadyAdmin = newLabelsSet.contains('admin');

    if (alreadyAdmin) {
      context.log('User $userId already has the "admin" label.');
      final response = {
        'success': true,
        'message': 'User already has the admin label.',
        'userId': userId,
        'labels': currentLabels, // Return current labels
      };
      context.log('Preparing to send "already admin" response...');
      return context.res.json(response);
    }

    // Add the 'admin' label
    newLabelsSet.add('admin');

    // Convert back to List<String> for the API call
    final List<String> updatedLabelsList = newLabelsSet.toList();
    context.log('Prepared updated labels: $updatedLabelsList'); // Log before update

    // --- CRITICAL STEP ---
    context.log('Attempting users.updateLabels for $userId...');
    await users.updateLabels(userId: userId, labels: updatedLabelsList);
    context.log('users.updateLabels call completed successfully for $userId.'); // Log right after update
    // --- END CRITICAL STEP ---

    context.log('Successfully added "admin" label logic completed for user: $userId');
    final response = {
      'success': true,
      'message': 'Admin label added successfully.',
      'userId': userId,
      'updatedLabels': updatedLabelsList,
    };
    context.log('Preparing to send success response...'); // Log before sending success
    return context.res.json(response);

  } on AppwriteException catch (e) {
    // Log the full error details from AppwriteException
    context.error(
        'Appwrite Error updating labels for user $userId: [${e.code}] ${e.message} | Type: ${e.type} | Response: ${e.response}');

    int statusCode = 500; // Default internal server error
    String errorMessage = 'Failed to update user labels due to Appwrite error.';

    // Refine error messages based on common codes
    if (e.code == 404) {
      statusCode = 404;
      errorMessage = 'User not found with ID: $userId';
    } else if (e.code == 400) {
      statusCode = 400;
      errorMessage = 'Bad request during label update: ${e.message}'; // Include Appwrite's message
    } else if (e.code == 401 || e.code == 403) {
       // Even if permissions *should* be ok, log this distinctively
      statusCode = 500; // Return 500 to client, but log specific potential cause
      errorMessage = 'Function configuration or permission error encountered.';
      context.error('Critical: Received 401/403. Double-check API Key scopes (users.read/users.write) and validity.');
    } else if (e.code == 409) {
       // Conflict - Might happen in rare race conditions?
       statusCode = 409;
       errorMessage = 'Conflict during update. User state might have changed.';
    } else if (e.code == 500) {
        // Server error on Appwrite's side
        statusCode = 503; // Service Unavailable might be more appropriate to client
        errorMessage = 'Appwrite server error during label update.';
    }

    final errorResponse = {
      'success': false,
      'error': errorMessage,
      'details': e.message, // Provide Appwrite message in details
      'code': e.code,     // Provide Appwrite code
    };
    context.log('Preparing to send Appwrite error response (Code: ${e.code})...'); // Log before sending error
    return context.res.json(errorResponse, statusCode: statusCode);

  } catch (e, stackTrace) {
    // Catch ALL other errors and log stack trace
    context.error('Generic unexpected error updating labels for user $userId: ${e.toString()}\nStackTrace: ${stackTrace}');
    final errorResponse = {
      'success': false,
      'error': 'An unexpected internal server error occurred.',
      'details': e.toString(), // Provide basic error string
    };
    context.log('Preparing to send generic error response...'); // Log before sending error
    return context.res.json(errorResponse, statusCode: 500);
  }
}
