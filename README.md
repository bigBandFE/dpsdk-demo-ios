# DPSDK iOS Demo App

This project demonstrates the integration of DragonPass DPSDK into an iOS application.

## Project Setup

Clone the repository and open `DPSDK-DEMO.xcodeproj` in Xcode. The DPSDK dependency is resolved automatically via Swift Package Manager.

## Getting Client ID

Open an Issue at **[github.com/bigBandFE/dpsdk-contact](https://github.com/bigBandFE/dpsdk-contact)** with your name, company, and email address. The DPSDK team will respond with your Client ID.

## Setting Client ID

In `DPSDK-DEMO/AppDelegate.swift`, replace the placeholder:

```
DPSDK.start(clientId: "CLIENT_ID")
```

## License

This project is provided as a reference integration sample.
