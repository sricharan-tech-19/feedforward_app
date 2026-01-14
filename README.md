🍽 FeedForward — AI-Powered Food Rescue Platform

FeedForward is a smart food-rescue platform that connects restaurants and donors with NGOs using AI + geolocation to reduce food waste and fight hunger.
Instead of NGOs manually calling restaurants or scrolling through long lists, FeedForward lets them type what they need in plain English, and the system finds the best matching nearby food donations automatically.

🚀 What Problem We Solve
Every day:
Restaurants throw away edible food
NGOs struggle to find food on time
Coordination is slow, manual, and unreliable
FeedForward fixes this by combining:
Real-time donation listings
AI-based request understanding
Location-based prioritization

🧠 Core Idea
NGOs don’t browse.
They describe what they need:
“We need veg food for 40 people near Anna Nagar urgently”

Our AI converts this into structured filters:

{
  "foodType": "veg",
  "quantityPeople": 40,
  "locationHint": "Anna Nagar",
  "urgency": "urgent"
}


The app then:
Filters Firestore donations
Uses geolocation to calculate distances
Sorts results by nearest donors first
Displays ranked matches to the NGO
So NGOs get the closest, best-fit food first, without losing access to others.

👥 User Roles
1️⃣ Donors

Restaurants, caterers, hostels, or individuals.

They can:
Upload food details
Add number of servings
Add pickup address
Upload food photo
Make their food visible to NGOs
Each donation is stored in Firebase with:
status = AVAILABLE

2️⃣ NGOs

NGOs do not manually search.

They:
Enter a natural-language request
See AI-ranked food matches

Claim donations
When an NGO claims food:
status = CLAIMED
claimedBy = ngoUserId


This prevents multiple NGOs from taking the same donation.

🤖 AI System
FeedForward uses:
Groq + LLaMA 3.1 for natural-language understanding
Flask AI backend to process NGO requests
The AI’s only job:

Convert messy human text into clean structured filters
The database + app handle:
Matching
Sorting
Fairness
Safety

This avoids hallucinations and keeps the system reliable.

📍 Geolocation Logic
Donor addresses are converted into latitude & longitude
NGO request location is also geocoded
Donations are ranked by distance

This ensures:
Nearby food appears first — but far-away food is still visible.
So NGOs get priority matching, not blind filtering.

🧱 Tech Stack
Frontend

Flutter
Firebase Authentication
Cloud Firestore
Firebase Storage
Geocoding API
Backend (AI)
Python
Flask
Groq LLaMA API

🔥 Why This Is Different

Most apps are:
Manual
Slow
Location-blind
Hard for NGOs
FeedForward is:
AI-driven
Distance-aware
Real-time
Built for NGO workflows

NGOs don’t “search”.
They ask — and the system works for them.

🧩 Current Status
✔ Donor upload system
✔ NGO smart search
✔ AI parsing
✔ Distance-based ranking
✔ Claiming workflow
✔ Firebase integration

💡 Vision
FeedForward can scale city-wide:
Every restaurant becomes a food node
Every NGO gets instant access
Food reaches people before it is wasted

This is not a listing app.
This is a real-time food rescue network.
