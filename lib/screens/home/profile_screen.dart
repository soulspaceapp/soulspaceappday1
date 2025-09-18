import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login_screen.dart'; // adjust path to your login screen

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _loading = true;
  String name = '';
  String email = '';
  String avatar = '';
  final List<String> avatarOptions = [
    'https://i.pravatar.cc/150?img=1',
    'https://i.pravatar.cc/150?img=2',
    'https://i.pravatar.cc/150?img=3',
    'https://i.pravatar.cc/150?img=4',
    'https://i.pravatar.cc/150?img=5',
  ];
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    final data = doc.exists ? (doc.data() ?? {}) : {};
    setState(() {
      name = (data['name'] as String?) ?? (user!.displayName ?? 'Anonymous');
      email = (data['email'] as String?) ?? (user!.email ?? '');
      avatar = (data['avatar'] as String?) ?? avatarOptions.first;
      _nameController.text = name;
      _loading = false;
    });
  }

  Future<void> _updateProfile() async {
    if (user == null) return;
    final newName = _nameController.text.trim();
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
      'name': newName.isEmpty ? name : newName,
      'avatar': avatar,
      'email': email,
    }, SetOptions(merge: true));
    setState(() {
      name = newName.isEmpty ? name : newName;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    // navigate to login - adjust path/import if needed
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (user == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Not signed in'),
            ElevatedButton(onPressed: _logout, child: const Text('Go to Login')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            CircleAvatar(radius: 50, backgroundImage: NetworkImage(avatar)),
            const SizedBox(height: 12),
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(email, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),

            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display name')),

            const SizedBox(height: 12),
            const Text('Choose avatar:'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: avatarOptions.map((a) {
                final selected = a == avatar;
                return GestureDetector(
                  onTap: () async {
                    setState(() => avatar = a);
                    await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({'avatar': a}, SetOptions(merge: true));
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(radius: 28, backgroundImage: NetworkImage(a)),
                      if (selected)
                        const Positioned(
                          right: -2,
                          bottom: -2,
                          child: Icon(Icons.check_circle, color: Colors.green, size: 22),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),
            ElevatedButton(onPressed: _updateProfile, child: const Text('Save')),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _logout, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Log out')),
          ],
        ),
      ),
    );
  }
}
