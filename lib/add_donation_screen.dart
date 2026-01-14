// lib/add_donation_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';

class AddDonationScreen extends StatefulWidget {
  const AddDonationScreen({super.key});

  @override
  State<AddDonationScreen> createState() => _AddDonationScreenState();
}

class _AddDonationScreenState extends State<AddDonationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _foodNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _servingsController = TextEditingController();
  final _addressController = TextEditingController();

  String _vegNonVeg = 'veg';
  File? _imageFile;
  bool _isLoading = false;
  bool _isUploadingImage = false;
  bool _isGeocoding = false;

  @override
  void dispose() {
    _foodNameController.dispose();
    _descriptionController.dispose();
    _servingsController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to take photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    setState(() => _isUploadingImage = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final fileName = "${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final ref = FirebaseStorage.instance.ref().child("donations/$fileName");

      // Upload file
      await ref.putFile(_imageFile!);

      // Get download URL
      final downloadUrl = await ref.getDownloadURL();

      setState(() => _isUploadingImage = false);

      return downloadUrl;
    } catch (e) {
      debugPrint("Image upload error: $e");
      setState(() => _isUploadingImage = false);

      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to upload image. Continuing without image.'),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }
  }

  Future<void> _submitDonation() async {
    if (!_formKey.currentState!.validate()) return;

    if (_imageFile == null) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No Image Selected'),
          content: const Text(
              'Are you sure you want to continue without an image? Photos help NGOs identify food better.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Add Image'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      );

      if (shouldContinue != true) return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Step 1: Upload image (if exists)
      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage();
      }

      // Step 2: Geocode address
      setState(() => _isGeocoding = true);

      double? lat;
      double? lng;

      try {
        final locations = await locationFromAddress(
          _addressController.text.trim(),
        ).timeout(const Duration(seconds: 10));

        if (locations.isNotEmpty) {
          lat = locations.first.latitude;
          lng = locations.first.longitude;
        }
      } catch (e) {
        debugPrint("Geocoding failed: $e");

        if (!mounted) return;

        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Address Not Found'),
            content: Text(
              'Could not find the location for: ${_addressController.text}\n\n'
              'Please check the address and try again, or continue without location data (not recommended).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Fix Address'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue Anyway'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          setState(() {
            _isLoading = false;
            _isGeocoding = false;
          });
          return;
        }
      } finally {
        setState(() => _isGeocoding = false);
      }

      // Step 3: Save to Firestore
      final donationData = {
        "foodName": _foodNameController.text.trim(),
        "description": _descriptionController.text.trim(),
        "vegNonVeg": _vegNonVeg,
        "servings": int.parse(_servingsController.text.trim()),
        "donorId": uid,
        "status": "AVAILABLE",
        "address": _addressController.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
      };

      // Add optional fields
      if (imageUrl != null) {
        donationData["imageUrl"] = imageUrl;
      }
      if (lat != null && lng != null) {
        donationData["lat"] = lat;
        donationData["lng"] = lng;
      }

      await FirebaseFirestore.instance
          .collection("donations")
          .add(donationData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Donation added successfully! 🎉"),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint("Submit error: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Donation"),
        actions: [
          if (_imageFile != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                setState(() => _imageFile = null);
              },
              tooltip: 'Remove image',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Image Picker Section
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                ),
                child: _imageFile != null
                    ? Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              _imageFile!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          if (_isUploadingImage)
                            Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Uploading image...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 60,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add food photo',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '(Optional but recommended)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Food Name
            TextFormField(
              controller: _foodNameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Food Name *",
                hintText: "e.g., Biryani, Sambar Rice",
                prefixIcon: Icon(Icons.restaurant),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return "Please enter food name";
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Description *",
                hintText: "Describe the food, ingredients, etc.",
                prefixIcon: Icon(Icons.description),
                alignLabelWithHint: true,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return "Please enter description";
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Veg/Non-Veg Selector
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 8),
                  child: Text(
                    'Food Type *',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'veg',
                        groupValue: _vegNonVeg,
                        onChanged: (value) {
                          setState(() => _vegNonVeg = value!);
                        },
                        title: const Text('Vegetarian'),
                        subtitle: const Text('🥗 Veg'),
                        activeColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _vegNonVeg == 'veg'
                                ? Colors.green
                                : Colors.grey[300]!,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'non-veg',
                        groupValue: _vegNonVeg,
                        onChanged: (value) {
                          setState(() => _vegNonVeg = value!);
                        },
                        title: const Text('Non-Veg'),
                        subtitle: const Text('🍗 Non-Veg'),
                        activeColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _vegNonVeg == 'non-veg'
                                ? Colors.red
                                : Colors.grey[300]!,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Servings
            TextFormField(
              controller: _servingsController,
              decoration: const InputDecoration(
                labelText: "Number of Servings *",
                hintText: "e.g., 50",
                prefixIcon: Icon(Icons.people),
                helperText: 'Approximate number of people this can feed',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return "Please enter number of servings";
                }
                final num = int.tryParse(v.trim());
                if (num == null || num <= 0) {
                  return "Please enter a valid number";
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Address
            TextFormField(
              controller: _addressController,
              textCapitalization: TextCapitalization.words,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Pickup Address *",
                hintText: "123 Main St, Anna Nagar, Chennai, Tamil Nadu",
                prefixIcon: Icon(Icons.location_on),
                alignLabelWithHint: true,
                helperText: 'Include area, city, and state for best results',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return "Please enter pickup address";
                }
                if (v.trim().length < 10) {
                  return "Please enter a complete address";
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Status indicators
            if (_isGeocoding)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Finding location coordinates...'),
                  ],
                ),
              ),

            if (_isGeocoding) const SizedBox(height: 16),

            // Submit Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_isLoading || _isUploadingImage || _isGeocoding)
                    ? null
                    : _submitDonation,
                child: (_isLoading || _isUploadingImage || _isGeocoding)
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isUploadingImage
                                ? 'Uploading image...'
                                : _isGeocoding
                                    ? 'Finding location...'
                                    : 'Submitting...',
                          ),
                        ],
                      )
                    : const Text('Submit Donation'),
              ),
            ),
            const SizedBox(height: 16),

            // Info text
            Text(
              '* Required fields',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
