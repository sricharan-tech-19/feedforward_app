import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math' as math;
import 'services/ai_services.dart';
import 'role_select_screen.dart';

class NgoHomeScreen extends StatefulWidget {
  const NgoHomeScreen({super.key});

  @override
  State<NgoHomeScreen> createState() => _NgoHomeScreenState();
}

class _NgoHomeScreenState extends State<NgoHomeScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  bool _geocoding = false;
  List<Map<String, dynamic>>? _results;
  String? _errorMessage;
  Map<String, dynamic>? _appliedFilters;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
      (_) => false,
    );
  }

  /// Calculate distance using Haversine formula (proper geographic distance)
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c; // Distance in kilometers
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  Future<void> _search() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your food requirements')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _results = null;
      _errorMessage = null;
    });

    try {
      // 🤖 Step 1: AI converts natural language to structured filters
      final aiResponse = await AiService.parseQuery(_controller.text);
      final filters = aiResponse["filters"] ?? {};

      // 🔥 DEBUG: Print what AI extracted
      print('=== AI EXTRACTED FILTERS ===');
      print('  Food Name: ${filters["foodName"]}');
      print('  Food Type: ${filters["foodType"]}');
      print('  Quantity: ${filters["quantityPeople"]}');
      print('  Location: ${filters["locationHint"]}');
      print('  Urgency: ${filters["urgency"]}');
      print('===========================');

      setState(() {
        _appliedFilters = filters;
      });

      // 🌍 Step 2: Get target location coordinates
      double targetLat = 13.0827; // Chennai fallback
      double targetLng = 80.2707;

      if (filters["locationHint"] != null &&
          filters["locationHint"].toString().isNotEmpty) {
        setState(() => _geocoding = true);

        try {
          final locations = await locationFromAddress(
            filters["locationHint"],
          ).timeout(const Duration(seconds: 8));

          if (locations.isNotEmpty) {
            targetLat = locations.first.latitude;
            targetLng = locations.first.longitude;
            print('📍 Found location: $targetLat, $targetLng');
          }
        } catch (e) {
          debugPrint("Geocoding failed for ${filters['locationHint']}: $e");
          // Continue with fallback coordinates
        } finally {
          if (mounted) {
            setState(() => _geocoding = false);
          }
        }
      }

      // 🔍 Step 3: Query Firestore with filters
      Query query = FirebaseFirestore.instance
          .collection("donations")
          .where("status", isEqualTo: "AVAILABLE");

      // Apply food type filter
      if (filters["foodType"] != null &&
          filters["foodType"].toString().isNotEmpty) {
        print('🔍 Filtering by foodType: ${filters["foodType"]}');
        query = query.where("vegNonVeg", isEqualTo: filters["foodType"]);
      }

      // Apply food name filter (optional - only if exact match exists)
      // Note: For better results, consider implementing fuzzy search
      if (filters["foodName"] != null &&
          filters["foodName"].toString().isNotEmpty) {
        print('🔍 Searching for foodName: ${filters["foodName"]}');
        // Uncomment if your Firestore has foodName field with exact matches
        // query = query.where("foodName", isEqualTo: filters["foodName"]);
      }

      // Apply quantity filter
      if (filters["quantityPeople"] != null) {
        print('🔍 Filtering by servings >= ${filters["quantityPeople"]}');
        query = query.where(
          "servings",
          isGreaterThanOrEqualTo: filters["quantityPeople"],
        );
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;

      print('📦 Found ${docs.length} matching donations');

      if (docs.isEmpty) {
        setState(() {
          _results = [];
          _loading = false;
          _errorMessage =
              'No matching donations found. Try adjusting your search.';
        });
        return;
      }

      // 📍 Step 4: Ensure all donations have coordinates
      List<Map<String, dynamic>> enrichedDonations = [];

      for (var doc in docs) {
        final data =
            Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        data['id'] = doc.id;

        // Check if coordinates exist
        if (!data.containsKey("lat") || !data.containsKey("lng")) {
          try {
            final address = data["address"] ?? "";
            if (address.isNotEmpty) {
              final locations = await locationFromAddress(address)
                  .timeout(const Duration(seconds: 5));

              if (locations.isNotEmpty) {
                data["lat"] = locations.first.latitude;
                data["lng"] = locations.first.longitude;

                // Update Firestore for future queries
                await FirebaseFirestore.instance
                    .collection("donations")
                    .doc(doc.id)
                    .update({
                  "lat": data["lat"],
                  "lng": data["lng"],
                });
              }
            }
          } catch (e) {
            debugPrint("Failed to geocode ${doc.id}: $e");
            // Skip donations without valid coordinates
            continue;
          }
        }

        // Calculate distance
        if (data.containsKey("lat") && data.containsKey("lng")) {
          data['distance'] = _calculateDistance(
            targetLat,
            targetLng,
            data["lat"] as double,
            data["lng"] as double,
          );
        } else {
          data['distance'] = double.infinity;
        }

        // Add urgency flag from filters
        data['isUrgent'] = filters["urgency"] == "urgent";

        enrichedDonations.add(data);
      }

      // 🔥 Step 5: Sort by urgency first, then distance
      enrichedDonations.sort((a, b) {
        // If request is urgent, prioritize closer donations
        if (a['isUrgent'] == true) {
          final distA = a['distance'] ?? double.infinity;
          final distB = b['distance'] ?? double.infinity;
          return distA.compareTo(distB);
        }

        // Otherwise just sort by distance
        final distA = a['distance'] ?? double.infinity;
        final distB = b['distance'] ?? double.infinity;
        return distA.compareTo(distB);
      });

      print('✅ Search completed with ${enrichedDonations.length} results');

      if (mounted) {
        setState(() {
          _results = enrichedDonations;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Search failed. Please try again.';
          _results = [];
        });
      }
    }
  }

  Future<void> _claimDonation(String docId, String foodName) async {
    try {
      await FirebaseFirestore.instance
          .collection('donations')
          .doc(docId)
          .update({
        'status': 'CLAIMED',
        'claimedBy': FirebaseAuth.instance.currentUser!.uid,
        'claimedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully claimed: $foodName'),
          backgroundColor: Colors.green,
        ),
      );

      // Remove from results
      setState(() {
        _results?.removeWhere((item) => item['id'] == docId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to claim donation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showProfileDialog(BuildContext context, String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile'),
        content: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final userData = snapshot.data!.data() as Map<String, dynamic>?;
            if (userData == null) {
              return const Text('No profile data found');
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileRow(
                  icon: Icons.person,
                  label: 'Contact Person',
                  value: userData['name'] ?? 'N/A',
                ),
                const SizedBox(height: 12),
                if (userData['organizationName'] != null) ...[
                  _ProfileRow(
                    icon: Icons.business,
                    label: 'Organization',
                    value: userData['organizationName'],
                  ),
                  const SizedBox(height: 12),
                ],
                _ProfileRow(
                  icon: Icons.phone,
                  label: 'Phone',
                  value: '+91 ${userData['phone'] ?? 'N/A'}',
                ),
                const SizedBox(height: 12),
                _ProfileRow(
                  icon: Icons.email,
                  label: 'Email',
                  value: userData['email'] ?? 'N/A',
                ),
                const SizedBox(height: 12),
                const _ProfileRow(
                  icon: Icons.badge,
                  label: 'Role',
                  value: 'NGO',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NGO Smart Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => _showProfileDialog(context, currentUserId),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // AI-Powered Search Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AI-powered search: Just describe what you need!',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Search Input
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText:
                        'Example: "Need chicken meals for 50 people near Anna Nagar urgently"',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 12),

                // Search Button
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _search,
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(_loading ? 'Searching...' : 'Search Donations'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFC8019),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),

                // Applied Filters Display
                if (_appliedFilters != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_appliedFilters!['foodName'] != null)
                        Chip(
                          avatar: const Icon(Icons.restaurant, size: 16),
                          label: Text(_appliedFilters!['foodName'].toString()),
                          backgroundColor: Colors.purple.shade50,
                        ),
                      if (_appliedFilters!['foodType'] != null)
                        Chip(
                          label: Text(_appliedFilters!['foodType']
                              .toString()
                              .toUpperCase()),
                          backgroundColor: _appliedFilters!['foodType'] == 'veg'
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                        ),
                      if (_appliedFilters!['quantityPeople'] != null)
                        Chip(
                          avatar: const Icon(Icons.people, size: 16),
                          label: Text(
                              '${_appliedFilters!['quantityPeople']} people'),
                          backgroundColor: Colors.blue.shade50,
                        ),
                      if (_appliedFilters!['locationHint'] != null)
                        Chip(
                          avatar: const Icon(Icons.location_on, size: 16),
                          label:
                              Text(_appliedFilters!['locationHint'].toString()),
                          backgroundColor: Colors.orange.shade50,
                        ),
                      if (_appliedFilters!['urgency'] != null)
                        Chip(
                          avatar: const Icon(Icons.warning, size: 16),
                          label: Text(_appliedFilters!['urgency']
                              .toString()
                              .toUpperCase()),
                          backgroundColor: Colors.red.shade50,
                        ),
                    ],
                  ),
                ],

                // Geocoding Indicator
                if (_geocoding)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Finding location...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Results Section
          Expanded(
            child: _buildResultsSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_results == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Describe what food you need',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'AI will help you find the best matching donations',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    }

    if (_results!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No matching donations',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search criteria',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _results!.length,
      itemBuilder: (context, index) {
        final data = _results![index];
        return _DonationCard(
          data: data,
          onClaim: () => _claimDonation(data['id'], data['foodName']),
        );
      },
    );
  }
}

class _DonationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onClaim;

  const _DonationCard({
    required this.data,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final distance = data['distance'];
    final distanceText = distance != null && distance != double.infinity
        ? '${distance.toStringAsFixed(1)} km away'
        : 'Distance unknown';

    final isUrgent = data['isUrgent'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUrgent ? Border.all(color: Colors.red, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (data['imageUrl'] != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Image.network(
                data['imageUrl'],
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Icon(Icons.image_not_supported, size: 50),
                  );
                },
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Badges Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['foodName'] ?? 'Unknown Food',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    // Veg/Non-Veg Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: data['vegNonVeg'] == 'veg'
                            ? Colors.green
                            : Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data['vegNonVeg'] == 'veg' ? 'VEG' : 'NON-VEG',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Urgent Badge
                    if (isUrgent) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'URGENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 8),

                // Description
                if (data['description'] != null)
                  Text(
                    data['description'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                const SizedBox(height: 12),

                // Servings and Distance
                Row(
                  children: [
                    Icon(Icons.people_outline,
                        size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${data['servings']} servings',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.location_on,
                        size: 18, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      distanceText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Address
                if (data['address'] != null)
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          data['address'],
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 16),

                // Claim Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: onClaim,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Claim This Donation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFC8019),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
