import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Core Firebase
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore
import 'package:http/http.dart' as http; // For Cloud Functions
import 'package:intl/intl.dart';
import 'package:plant_tracker/firebase_options.dart'; // For date formatting

// --- Configuration ---
// TODO: Replace with your actual Cloud Function URLs
const String setFanStateUrl =
    'https://set-fan-state-971602190698.us-central1.run.app';
// TODO: Replace with the userId of the device you want to track
const String targetUserId = 'user_1';
// --- End Configuration ---

// --- Thresholds ---
const double lowMoistureThreshold =
    30.0; // Percentage below which watering is needed
const double lowLightThreshold = 300; // Lux below which light is considered low
const double highLightThreshold =
    2000; // Lux above which light is considered high/direct
// --- End Thresholds ---

// Initialize Firebase - THIS IS CRUCIAL
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Ensure you have configured Firebase for your platform (Android/iOS/Web)
  // Add your FirebaseOptions here if needed, or ensure config files are present
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // If using FlutterFire CLI
  );
  runApp(const PlantTrackerApp());
}

class PlantTrackerApp extends StatelessWidget {
  const PlantTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plant Tracker',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.green[50], // Light green background
        fontFamily: 'Sans-serif', // Optional: Choose a nice font
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          elevation: 2.0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Colors.blue[600], // Water color
          linearTrackColor: Colors.brown[100], // Soil color
        ),
        buttonTheme: ButtonThemeData(
          buttonColor: Colors.green[600],
          textTheme: ButtonTextTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
        ),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.green,
        ).copyWith(secondary: Colors.amber[600]), // Accent color
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Main Screen Widget
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ApiService _apiService = ApiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Plant Tracker 🌱'),
        centerTitle: true,
      ),
      body: ListView(
        // Use ListView for scrollability if content grows
        padding: const EdgeInsets.all(16.0),
        children: [
          // StreamBuilder for latest sensor data
          StreamBuilder<DocumentSnapshot?>(
            stream: _firestoreService.getLatestSensorDataStream(targetUserId),
            builder: (context, sensorSnapshot) {
              if (sensorSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (sensorSnapshot.hasError) {
                print("Sensor Stream Error: ${sensorSnapshot.error}");
                return const Center(
                  child: Text(
                    'Error loading sensor data.',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              }
              if (!sensorSnapshot.hasData ||
                  sensorSnapshot.data == null ||
                  !sensorSnapshot.data!.exists) {
                return const Center(child: Text('No sensor data found yet.'));
              }

              // Extract data safely
              final data = sensorSnapshot.data!.data() as Map<String, dynamic>?;
              final vcnl = data?['vcnlDetails'] as Map<String, dynamic>?;
              final sht = data?['shtDetails'] as Map<String, dynamic>?;
              final other = data?['otherDetails'] as Map<String, dynamic>?;

              final double temp = (sht?['temp'] as num?)?.toDouble() ?? 0.0;
              final double humidity = (sht?['rHum'] as num?)?.toDouble() ?? 0.0;
              final int ambientLight = (vcnl?['al'] as num?)?.toInt() ?? 0;
              final Timestamp? timestamp =
                  other?['cloudUploadTime'] as Timestamp?;
              final String lastUpdated =
                  timestamp != null
                      ? DateFormat('MMM d, hh:mm a').format(timestamp.toDate())
                      : 'N/A';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Last Updated: $lastUpdated',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Water Level Section
                  _buildWaterLevelSection(humidity),
                  const SizedBox(height: 20),

                  // Current Conditions Section
                  _buildConditionsSection(temp, ambientLight),
                  const SizedBox(height: 20),

                  // Fan Control Section (uses a separate StreamBuilder)
                  _buildFanControlSection(),
                  const SizedBox(height: 20),

                  // Optional: Raw Sensor Values (Example)
                  _buildRawDataSection(vcnl, sht),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // --- UI Building Helper Methods ---

  Widget _buildWaterLevelSection(double humidity) {
    String waterStatus;
    Color waterColor;
    IconData waterIcon;

    if (humidity < lowMoistureThreshold) {
      waterStatus = 'Needs Watering!';
      waterColor = Colors.red[400]!;
      waterIcon = Icons.warning_amber_rounded;
    } else if (humidity < 60) {
      // Example threshold for "Okay"
      waterStatus = 'Soil Moisture Okay';
      waterColor = Colors.blue[600]!;
      waterIcon = Icons.opacity; // Water drop
    } else {
      waterStatus = 'Soil is Moist';
      waterColor = Colors.blue[800]!;
      waterIcon = Icons.water_drop_rounded;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Soil Moisture',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Fun Water Level Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: LinearProgressIndicator(
                value: humidity / 100.0, // Normalize humidity to 0.0 - 1.0
                minHeight: 25,
                backgroundColor:
                    Theme.of(context).progressIndicatorTheme.linearTrackColor,
                valueColor: AlwaysStoppedAnimation<Color>(waterColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${humidity.toStringAsFixed(1)}%', // Show percentage
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: waterColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(waterIcon, color: waterColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  waterStatus,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: waterColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionsSection(double temp, int ambientLight) {
    String lightStatus;
    Color lightColor;
    IconData lightIcon;

    if (ambientLight < lowLightThreshold) {
      lightStatus = 'Low Light';
      lightColor = Colors.orange[600]!;
      lightIcon = Icons.lightbulb_outline_rounded;
    } else if (ambientLight > highLightThreshold) {
      lightStatus = 'Bright Light';
      lightColor = Colors.yellow[700]!;
      lightIcon = Icons.wb_sunny_rounded;
    } else {
      lightStatus = 'Good Light';
      lightColor = Colors.green[600]!;
      lightIcon = Icons.lightbulb_rounded;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
        child: Column(
          children: [
            Text(
              'Current Conditions',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(
                  icon: Icons.thermostat_rounded,
                  label: 'Temperature',
                  value: '${temp.toStringAsFixed(1)}°C',
                  color: Colors.redAccent,
                ),
                _buildInfoChip(
                  icon: lightIcon,
                  label: lightStatus, // Dynamic label based on status
                  value: '$ambientLight lux',
                  color: lightColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFanControlSection() {
    return StreamBuilder<DocumentSnapshot?>(
      stream: _firestoreService.getDeviceControlStateStream(targetUserId),
      builder: (context, controlSnapshot) {
        bool currentFanState = false; // Default to off
        bool isLoading = false;
        bool hasError = false;

        if (controlSnapshot.connectionState == ConnectionState.waiting) {
          isLoading = true;
        } else if (controlSnapshot.hasError) {
          print("Control Stream Error: ${controlSnapshot.error}");
          hasError = true;
        } else if (controlSnapshot.hasData &&
            controlSnapshot.data != null &&
            controlSnapshot.data!.exists) {
          final controlData =
              controlSnapshot.data!.data() as Map<String, dynamic>?;
          currentFanState = (controlData?['fanState'] as bool?) ?? false;
        } else {
          // No control document yet, assume fan is off
          currentFanState = false;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.air_rounded,
                      color: currentFanState ? Colors.blueAccent : Colors.grey,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Air Circulation Fan',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (hasError)
                  const Icon(Icons.error_outline, color: Colors.red)
                else
                  Switch(
                    value: currentFanState,
                    activeColor: Colors.blueAccent,
                    onChanged: (newState) async {
                      // Call the Cloud Function to update the state
                      bool success = await _apiService.setFanState(
                        targetUserId,
                        newState,
                      );
                      if (!success && mounted) {
                        // Show error if the call failed
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to update fan state. Check connection.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      // Note: UI updates automatically via StreamBuilder listening to Firestore
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRawDataSection(
    Map<String, dynamic>? vcnl,
    Map<String, dynamic>? sht,
  ) {
    // Example of showing raw data if needed
    return ExpansionTile(
      title: const Text('Raw Sensor Data'),
      leading: const Icon(Icons.raw_on_rounded),
      childrenPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
      children: [
        if (vcnl != null) ...[
          Text('VCNL Proximity: ${vcnl['prox'] ?? 'N/A'}'),
          Text('VCNL Ambient Light: ${vcnl['al'] ?? 'N/A'} lux'),
          Text('VCNL White Light: ${vcnl['wl'] ?? 'N/A'}'),
          const SizedBox(height: 8),
        ],
        if (sht != null) ...[
          Text(
            'SHT Temperature: ${(sht['temp'] as num?)?.toStringAsFixed(1) ?? 'N/A'} °C',
          ),
          Text(
            'SHT Humidity: ${(sht['rHum'] as num?)?.toStringAsFixed(1) ?? 'N/A'} %',
          ),
        ],
        if (vcnl == null && sht == null)
          const Text('No detailed data available.'),
      ],
    );
  }
}

// --- Service Classes ---

// Service to interact with Firestore
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _rootCollection =
      'plant-data-collection'; // Your root collection

  // Gets a stream of the latest sensor data document
  Stream<DocumentSnapshot?> getLatestSensorDataStream(String userId) {
    try {
      return _db
          .collection(_rootCollection)
          .doc(userId)
          .collection('dataPoints')
          .orderBy(
            'otherDetails.cloudUploadTime',
            descending: true,
          ) // Order by timestamp
          .limit(1) // Get only the latest one
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.isNotEmpty ? snapshot.docs.first : null,
          )
          .handleError((error) {
            print("Error fetching latest sensor data: $error");
            return null; // Propagate null on error
          });
    } catch (e) {
      print("Exception setting up sensor stream: $e");
      return Stream.value(null); // Return stream with null if setup fails
    }
  }

  // Gets a stream of the device control state document
  Stream<DocumentSnapshot?> getDeviceControlStateStream(String userId) {
    try {
      return _db
          .collection(_rootCollection)
          .doc(userId)
          .collection('control')
          .doc('deviceState')
          .snapshots() // Listen to real-time changes
          .handleError((error) {
            print("Error fetching control state: $error");
            return null; // Propagate null on error
          });
    } catch (e) {
      print("Exception setting up control stream: $e");
      return Stream.value(null); // Return stream with null if setup fails
    }
  }
}

// Service to interact with Cloud Functions
class ApiService {
  // Calls the setFanState Cloud Function
  Future<bool> setFanState(String userId, bool desiredState) async {
    if (setFanStateUrl == 'YOUR_SET_FAN_STATE_FUNCTION_URL') {
      print("ERROR: setFanStateUrl is not configured!");
      return false;
    }
    try {
      final response = await http.post(
        Uri.parse(setFanStateUrl),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'userId': userId,
          'fanState': desiredState,
        }),
      );

      if (response.statusCode == 200) {
        print('Successfully set fan state via API: ${response.body}');
        return true;
      } else {
        print(
          'Failed to set fan state via API. Status: ${response.statusCode}, Body: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      print('Error calling setFanState API: $e');
      return false;
    }
  }
}
