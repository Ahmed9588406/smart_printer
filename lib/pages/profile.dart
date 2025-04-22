// user_profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({Key? key}) : super(key: key);

  @override
  _UserProfileScreenState createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  File? _imageFile;
  String? _imageUrl;
  bool _isLoading = false;
  bool _isEditing = false;
  Map<String, dynamic>? _currentProfile;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _currentProfile = response;
          _firstNameController.text = response['first_name'] ?? '';
          _lastNameController.text = response['last_name'] ?? '';
          _phoneController.text = response['phone'] ?? '';
          _imageUrl = response['image_url'];
        });
      } else {
        // Initialize with default values for new users
        _currentProfile = {'coins': '30'};
      }
    } catch (e) {
      print('Error loading profile: $e'); // Debug log
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    setState(() {
      _isLoading = true;
    });

    try {
      final String fileName =
          '${const Uuid().v4()}${path.extension(_imageFile!.path)}';

      await _supabase.storage.from('images').upload(fileName, _imageFile!);

      final String imageUrl =
          _supabase.storage.from('images').getPublicUrl(fileName);

      return imageUrl;
    } catch (e) {
      print('Error uploading image: $e'); // Add this line for debugging
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
      return null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUserProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String? imageUrl = _imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage();
      }

      final profileData = {
        'id': user.id,
        'first_name': _firstNameController.text,
        'last_name': _lastNameController.text,
        'phone': _phoneController.text,
        'image_url': imageUrl,
        'coins': _currentProfile?['coins'] ??
            '30', // Preserve existing coins or set default
      };

      await _supabase.from('user_profiles').upsert(profileData);

      setState(() {
        _isEditing = false;
        _imageUrl = imageUrl;
        _currentProfile = profileData;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully!')),
      );

      // Reload profile to ensure UI is in sync with database
      await _loadUserProfile();
    } catch (e) {
      print('Error saving profile: $e'); // Debug log
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildEditableField(
    TextEditingController controller,
    String label,
    IconData icon,
    String? Function(String?) validator,
  ) {
    return Stack(
      alignment: Alignment.topRight,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
            enabled: _isEditing,
          ),
          validator: validator,
        ),
        if (!_isEditing)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        elevation: 2,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveUserProfile,
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.cancel),
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  // Reset to original values
                  if (_currentProfile != null) {
                    _firstNameController.text =
                        _currentProfile!['first_name'] ?? '';
                    _lastNameController.text =
                        _currentProfile!['last_name'] ?? '';
                    _phoneController.text = _currentProfile!['phone'] ?? '';
                  }
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile Image
                    Center(
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: _imageFile != null
                                ? ClipOval(
                                    child: Image.file(
                                      _imageFile!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : _imageUrl != null
                                    ? ClipOval(
                                        child: Image.network(
                                          _imageUrl!,
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child,
                                              loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress
                                                            .expectedTotalBytes !=
                                                        null
                                                    ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                    : null,
                                              ),
                                            );
                                          },
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                            Icons.person,
                                            size: 60,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.grey,
                                      ),
                          ),
                          FloatingActionButton.small(
                            onPressed: _pickImage,
                            child: const Icon(Icons.camera_alt),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildEditableField(
                      _firstNameController,
                      'First Name',
                      Icons.person_outline,
                      (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your first name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildEditableField(
                      _lastNameController,
                      'Last Name',
                      Icons.person_outline,
                      (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your last name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildEditableField(
                      _phoneController,
                      'Phone Number',
                      Icons.phone,
                      (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your phone number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    if (!_isEditing && _currentProfile == null)
                      ElevatedButton(
                        onPressed: _saveUserProfile,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'CREATE PROFILE',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
