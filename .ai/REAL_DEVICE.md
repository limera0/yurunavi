# Real-Device and Ride Verification

Automated checks do not prove real-world behavior involving:

- GPS, stationary mode, dead reckoning, off-route, reroute, or arrival;
- voice timing or wording in motion;
- foreground/background lifecycle;
- floating overlay, PIP, permissions, or Android services;
- map rendering, GPU/memory behavior, or real-road route quality.

Before asking the Product Owner, AI must finish everything it can: investigation, implementation, automated tests, build/APK, logging, and a short reproducible check.

Ask for the minimum observable action in plain Korean, not technical diagnosis. Example: “Start and end navigation three times and tell me whether the black screen appears.”

Until evidence is recorded, report: `Automated verification complete; real-device verification pending.` Do not represent pending T3 behavior as fully verified or merge it to the release branch.
