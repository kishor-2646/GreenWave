# GreenWave 🌊 🚑

**GreenWave** is a real-time smart traffic clearance system designed to facilitate the "Green Wave" effect for emergency vehicles. By integrating live coordinate tracking, AI-powered auditory feedback, and a high-speed notification bridge, the platform ensures that ambulances can navigate through city junctions with minimal delay.

## 🚀 Key Features

* [cite_start]**Dual-Profile System**: Dedicated interfaces for **Ambulance Drivers** to broadcast emergencies and **Police Officers** to manage junction clearance.
* [cite_start]**Real-Time Path Optimization**: Uses the Google Directions API to calculate the most efficient route and visualizes it on a live map.
* [cite_start]**Firestore Notification Bridge**: A robust, low-latency signaling system that triggers system-level notifications on police devices via a Firestore listener the moment a broadcast starts.
* [cite_start]**AI "Talk Back" System**: Leverages **Gemini AI (TTS)** to provide hands-free auditory updates to both drivers and officers regarding junction status and ETA.
* [cite_start]**Dynamic Route Visualization**: The path color changes dynamically from **Purple** (Regular) to **Green** (Cleared) as police officers confirm signal clearance.
* [cite_start]**Resilient Session Recovery**: Re-entry logic ensures that active emergency broadcasts are automatically resumed if the driver exits the app.

## 🛠 Technical Approach

* [cite_start]**Real-Time Synchronization**: Leverages **Firebase Firestore** as a central state manager for low-latency coordinate and status updates between mobile nodes[cite: 1, 2, 3].
* [cite_start]**Hybrid Notification Bridge**: Uses a **Firestore-to-Hardware Bridge** to trigger system-level alerts via `flutter_local_notifications`, bypassing standard API restrictions.
* [cite_start]**Context-Aware Automation**: Uses Geofencing logic and polyline decoding to calculate "Collision Paths" between ambulance routes and assigned police junctions.
* [cite_start]**Adaptive Feedback Loop**: Integrates Gemini AI TTS to provide auditory guidance, throttled to maintain API efficiency.

## 🏗 System Architecture

The system operates across three primary layers:
1.  [cite_start]**Client Layer**: Flutter mobile applications for Ambulances and Police.
2.  [cite_start]**Communication Layer**: Firebase Firestore for real-time document streaming and local hardware notification drivers[cite: 1, 3].
3.  [cite_start]**Service Layer**: Google Directions API for pathfinding and Gemini AI for automated text-to-speech feedback.

## 📂 Project Structure

```text
lib/
├── core/
│   └── services/
│       ├── auth_service.dart      # User authentication logic
[cite_start]│       └── location_service.dart  # Real-time coordinate syncing [cite: 3]
├── views/
│   ├── ambulance/
│   │   ├── ambulance_dashboard.dart # Destination selection
[cite_start]│   │   └── ambulance_map_page.dart  # Broadcast & talk-back 
│   └── police/
[cite_start]│       └── police_map_page.dart     # Junction monitoring & clearing 
└── main.dart                        # Notification channel setup
```


## ⚙️ Setup & Installation
1. Prerequisites
Flutter SDK (v3.0.0+)

Firebase Project established in the Firebase Console

Google Cloud Project with Directions API, Maps SDK for Android, and Generative Language API enabled.

2. Configuration Files
Firebase: Download your google-services.json and place it in the android/app/ directory.

Environment: Create a .env file in the root directory with the following keys:

Code snippet
GOOGLE_MAPS_API_KEY=your_key_here
GEMINI_API_KEY=your_key_here
3. Build Configuration
Ensure Core Library Desugaring is enabled in your android/app/build.gradle.kts to support modern notification features:

Kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
4. Installation
Bash
# Clone the repository
git clone [https://github.com/kishor-2646/GreenWave.git](https://github.com/kishor-2646/GreenWave.git)

# Install dependencies
flutter pub get

# Run the application
flutter run
🚦 How it Works
Start Broadcast: The Ambulance Driver selects a destination. The app calculates the route and marks status as emergency in Firestore.


Police Alert: Police Officers receive a hardware-level notification and see the live path on their map.


Clear Junction: The officer clicks "Clear Traffic," triggering a green segment on the ambulance map.


Talk Back: Both users receive AI voice updates: "Alert. The junction has been cleared. Proceed with safety."
