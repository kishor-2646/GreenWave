\# GreenWave — Smart Ambulance Traffic Control System



GreenWave is a smart traffic management system designed to help emergency vehicles navigate traffic more efficiently through ambulance tracking, traffic signal coordination, and police monitoring.



\## Repository Structure



```text

GreenWave/

├── mobile/       # Flutter mobile application

└── backend/      # Spring Boot REST API

```



\## Tech Stack



\### Mobile

\- Flutter and Dart

\- Firebase Cloud Messaging

\- Google Maps and GPS

\- REST API integration



\### Backend

\- Java 21+

\- Spring Boot

\- PostgreSQL and PostGIS

\- JWT-based authentication

\- WebSocket-based real-time communication



\## Getting Started



\### Mobile Application



```powershell

cd mobile

flutter pub get

flutter run

```



Configure your local `.env` file using `.env.example` and provide the required API URL and API keys.



\### Backend



Open the `backend` directory in IntelliJ IDEA or another Java IDE. Configure the required environment variables and PostgreSQL/PostGIS connection, then run the Spring Boot application.



\## Development



\- `mobile/` contains the Flutter client.

\- `backend/` contains the Spring Boot server.

\- Keep secrets and local environment files out of version control.



\## License



No license has been specified yet.

