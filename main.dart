import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'security_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ==============================
// EMAIL OTP SERVICE
// ==============================
class EmailOtpService {
  static const String _emailJsServiceId = 'service_ynh4bdj';
  static const String _emailJsTemplateId = 'template_yoeyqvm';
  static const String _emailJsPublicKey = 'yvIdIDNWPSP5_B7u_';

  static String _generateOtp() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  static Future<String?> sendOtp(String toEmail) async {
    final otp = _generateOtp();
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _emailJsServiceId,
          'template_id': _emailJsTemplateId,
          'user_id': _emailJsPublicKey,
          'template_params': {
            'to_email': toEmail,
            'otp_code': otp,
            'app_name': 'Healthcare Security Toolkit',
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('EMAIL OTP SENT TO $toEmail');
        return otp;
      } else {
        debugPrint('EMAIL OTP FAILED: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('EMAIL OTP ERROR: $e');
      return null;
    }
  }
}

// ==============================
// MAIN
// ==============================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const HealthcareApp());
}

// ==============================
// MAIN APP
// ==============================
class HealthcareApp extends StatelessWidget {
  const HealthcareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Healthcare Security Toolkit',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      ),
      home: const LoginPage(),
    );
  }
}

// ==============================
// LOGIN PAGE
// ==============================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  int failedLoginAttempts = 0;

  Future<void> saveSecurityLog(String action) async {
    String encryptedAction = await SecurityService.encryptData(action);
    await FirebaseFirestore.instance.collection('security_logs').add({
      'action': encryptedAction,
      'timestamp': FieldValue.serverTimestamp(),
    });
    debugPrint("SECURITY LOG SAVED");
  }

  Future<void> _login() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter caregiver email and password"),
        ),
      );
      return;
    }

    if (failedLoginAttempts >= 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Too many login attempts. Try again later."),
          backgroundColor: Colors.red,
        ),
      );
      await saveSecurityLog("Multiple failed login attempts detected");
      debugPrint("LOGIN BLOCKED");
      return;
    }

    setState(() {
      _isLoading = true;
    });
    try {
      debugPrint("ATTEMPTING LOGIN");
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      failedLoginAttempts = 0;
      await saveSecurityLog("Caregiver login successful");
      debugPrint("LOGIN SUCCESS");
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TwoFactorPage(email: _emailController.text.trim()),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      failedLoginAttempts++;
      debugPrint("LOGIN ERROR");
      String message = "Login Failed";
      if (e.code == 'user-not-found') {
        message = "Caregiver account not found";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password";
      } else if (e.code == 'invalid-email') {
        message = "Invalid email format";
      }
      await saveSecurityLog("Failed login attempt");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Caregiver Authentication")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_person, size: 90, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              "Secure Elderly Monitoring Login",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Caregiver Email",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 25),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                    ),
                    onPressed: _login,
                    child: const Text("Secure Login"),
                  ),
          ],
        ),
      ),
    );
  }
}

// ==============================
// TWO FACTOR AUTHENTICATION
// ==============================
class TwoFactorPage extends StatefulWidget {
  final String email; // Parameter emel baharu
  const TwoFactorPage({super.key, required this.email});

  @override
  State<TwoFactorPage> createState() => _TwoFactorPageState();
}

class _TwoFactorPageState extends State<TwoFactorPage> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isCodeSent = false;
  String? _generatedOtp; // Penyimpan kod OTP sementara

  int failedOtpAttempts = 0;
  int resendCountdown = 60;
  Timer? countdownTimer;
  bool canResend = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      _sendOTP();
    });
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void startCountdown() {
    resendCountdown = 60;
    canResend = false;
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendCountdown == 0) {
        timer.cancel();
        if (mounted) {
          setState(() {
            canResend = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            resendCountdown--;
          });
        }
      }
    });
  }

  Future<void> saveSecurityLog(String action) async {
    String encryptedAction = await SecurityService.encryptData(action);
    await FirebaseFirestore.instance.collection('security_logs').add({
      'action': encryptedAction,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _sendOTP() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isCodeSent = false;
      });
    }

    try {
      startCountdown();
      // Menghantar OTP menggunakan API EmailJS
      final otp = await EmailOtpService.sendOtp(widget.email);

      if (otp != null) {
        _generatedOtp = otp;
        if (mounted) {
          setState(() {
            _isCodeSent = true;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("OTP dihantar ke ${widget.email}"),
              backgroundColor: Colors.green,
            ),
          );
          await saveSecurityLog("Email OTP sent to ${widget.email}");
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Unable to send OTP"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error communicating with OTP server"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _verifyOTP() async {
    String smsCode = _otpController.text.trim();

    if (smsCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter valid 6-digit OTP"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (failedOtpAttempts >= 5) {
      await saveSecurityLog("Multiple invalid OTP attempts detected");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Too many OTP attempts"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Simulasi kelewatan bagi mitigasi serangan 'brute-force' pantas
    await Future.delayed(const Duration(milliseconds: 600));

    // Pengecaman Logik: Padanan terus tanpa Firebase Auth
    if (smsCode == _generatedOtp) {
      await saveSecurityLog("Email OTP verification successful");
      if (mounted) {
        _navigateNext();
      }
    } else {
      failedOtpAttempts++;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Invalid OTP"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateNext() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSelectionPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("2FA Verification")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 90, color: Colors.green),
              const SizedBox(height: 20),
              Text(
                "OTP dihantar ke: \n${widget.email}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "000000",
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _isCodeSent ? _verifyOTP : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(250, 50),
                      ),
                      child: const Text(
                        "Verify OTP",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
              const SizedBox(height: 15),
              canResend
                  ? TextButton(
                      onPressed: _sendOTP,
                      child: const Text("Resend OTP"),
                    )
                  : Text("Resend OTP in $resendCountdown s"),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================
// PROFILE PAGE
// ==============================
class ProfileSelectionPage extends StatefulWidget {
  const ProfileSelectionPage({super.key});

  @override
  State<ProfileSelectionPage> createState() => _ProfileSelectionPageState();
}

class _ProfileSelectionPageState extends State<ProfileSelectionPage> {
  Future<void> _savePatient(String name, String age) async {
    String encryptedName = await SecurityService.encryptData(name);
    String encryptedAge = await SecurityService.encryptData(age);
    await FirebaseFirestore.instance.collection('patients').add({
      'name': encryptedName,
      'age': encryptedAge,
      'timestamp': FieldValue.serverTimestamp(),
    });
    debugPrint("PATIENT SAVED");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Authorized Elderly Profiles")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProfileCard(
              context,
              "FAKRIAH BINTI HASSAN",
              "61 Years Old",
              Icons.woman,
              Colors.pink,
            ),
            const SizedBox(height: 15),
            _buildProfileCard(
              context,
              "SHAHARUDIN BIN ABD RAHMAN",
              "66 Years Old",
              Icons.man,
              Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    String name,
    String age,
    IconData icon,
    Color color,
  ) {
    return InkWell(
      onTap: () async {
        await _savePatient(name, age);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardPage(
              name: name,
              age: age,
              icon: icon,
              color: color,
              role: "Caregiver",
            ),
          ),
        );
      },
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(icon, color: color),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(age),
          trailing: const Icon(Icons.arrow_forward_ios),
        ),
      ),
    );
  }
}

// ==============================
// DASHBOARD PAGE
// ==============================
class DashboardPage extends StatefulWidget {
  final String name;
  final String age;
  final IconData icon;
  final Color color;
  final String role;

  const DashboardPage({
    super.key,
    required this.name,
    required this.age,
    required this.icon,
    required this.color,
    required this.role,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? fallDetectionTimer;
  String selectedGraphTab = "Daily";

  @override
  void initState() {
    super.initState();
    // Preserving the security fall detection logic as requested
    fallDetectionTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      checkFallDetection();
    });
  }

  @override
  void dispose() {
    fallDetectionTimer?.cancel();
    super.dispose();
  }

  Future<void> saveAuditLog(String action) async {
    String encryptedAction = await SecurityService.encryptData(action);
    String encryptedUser = await SecurityService.encryptData(widget.name);

    await FirebaseFirestore.instance.collection('audit_logs').add({
      'user': encryptedUser,
      'action': encryptedAction,
      'timestamp': FieldValue.serverTimestamp(),
    });
    debugPrint("AUDIT LOG SAVED");
  }

  Future<void> checkFallDetection() async {
    try {
      double accelerometerValue = Random().nextDouble() * 30;
      if (accelerometerValue > 28) {
        String encryptedPatient = await SecurityService.encryptData(
          widget.name,
        );
        String encryptedValue = await SecurityService.encryptData(
          accelerometerValue.toStringAsFixed(2),
        );

        await FirebaseFirestore.instance.collection('emergency_alerts').add({
          'patient': encryptedPatient,
          'type': 'fall_detected',
          'accelerometer': encryptedValue,
          'status': 'critical',
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Fall Detected Emergency!"),
              backgroundColor: Colors.red,
            ),
          );
        }
        await saveAuditLog("Fall detection triggered");
      }
    } catch (e) {
      debugPrint("FALL DETECTION ERROR");
    }
  }

  Future<void> _handleSecureLogout() async {
    try {
      await saveAuditLog(
        "Caregiver manually logged out. Session terminated safely.",
      );
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session terminated securely."),
          backgroundColor: Colors.blueGrey,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint("LOGOUT ERROR: $e");
    }
  }

  Widget _buildSecurityShieldBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.gpp_good, color: Colors.blue, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "SECURITY GATEWAY ACTIVE",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Data Stream: AES-256 Encrypted | Audit Logging: Enabled",
                  style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "SECURE",
              style: TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMiniAuditLogs() {
    return Container(
      margin: const EdgeInsets.only(top: 25),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_toggle_off,
                color: Colors.blueGrey,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                "Live Security Audit Logs",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                "Live Feed",
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('audit_logs')
                .orderBy('timestamp', descending: true)
                .limit(3)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text(
                  "No audit logs captured in this session system.",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                );
              }

              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final timestamp = data['timestamp'] as Timestamp?;
                  final timeStr = timestamp != null
                      ? DateFormat('HH:mm:ss').format(timestamp.toDate())
                      : "--:--";

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "[$timeStr]",
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Encrypted Transaction Block Logged Successfully",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'Critical') return Colors.red;
    if (status == 'Warning' || status == 'Low') return Colors.amber;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Health Dashboard"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Secure Logout',
            onPressed: _handleSecureLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('health_records')
            .where('patientName', isEqualTo: widget.name)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          List<QueryDocumentSnapshot> docs = snapshot.hasData
              ? snapshot.data!.docs.toList()
              : [];
          // Sort in memory to avoid requiring complex Firestore indexes
          docs.sort((a, b) {
            Timestamp? tA = (a.data() as Map<String, dynamic>)['timestamp'];
            Timestamp? tB = (b.data() as Map<String, dynamic>)['timestamp'];
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          Map<String, dynamic>? latestRecord;
          if (docs.isNotEmpty) {
            latestRecord = docs.first.data() as Map<String, dynamic>;
          }

          String hrValue = latestRecord != null
              ? "${latestRecord['heartRate']}"
              : "--";
          String bpValue = latestRecord != null
              ? "${latestRecord['systolic']}/${latestRecord['diastolic']}"
              : "--/--";
          String lastUpdatedTime = latestRecord != null
              ? "${latestRecord['date']} ${latestRecord['time']}"
              : "No Data";

          bool hasCritical =
              latestRecord != null &&
              (latestRecord['hrStatus'] == 'Critical' ||
                  latestRecord['bpStatus'] == 'Critical');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecurityShieldBanner(),

                Card(
                  color: widget.color.withValues(alpha: 0.1),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: widget.color,
                      child: Icon(widget.icon, color: Colors.white),
                    ),
                    title: Text(
                      widget.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text("${widget.age} • Role: ${widget.role}"),
                    trailing: hasCritical
                        ? const Icon(Icons.warning, color: Colors.red, size: 30)
                        : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                ),
                const SizedBox(height: 15),

                // Manual Entry Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AddHealthDataPage(patientName: widget.name),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          "Add Data",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  HealthHistoryPage(patientName: widget.name),
                            ),
                          );
                        },
                        icon: const Icon(Icons.history),
                        label: const Text("Health History"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                if (latestRecord != null &&
                    latestRecord['notification'] != null &&
                    latestRecord['notification'].toString().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasCritical
                          ? Colors.red.shade50
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasCritical ? Colors.red : Colors.amber,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasCritical
                              ? Icons.error_outline
                              : Icons.warning_amber,
                          color: hasCritical ? Colors.red : Colors.amber,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            latestRecord['notification'],
                            style: TextStyle(
                              color: hasCritical
                                  ? Colors.red.shade900
                                  : Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const Text(
                  "Latest Vitals",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildVitalCard(
                      title: "Heart Rate",
                      value: hrValue,
                      unit: "BPM",
                      status: latestRecord != null
                          ? latestRecord['hrStatus']
                          : "No Data",
                      lastUpdated: lastUpdatedTime,
                      icon: Icons.favorite,
                    ),
                    _buildVitalCard(
                      title: "Blood Pressure",
                      value: bpValue,
                      unit: "mmHg",
                      status: latestRecord != null
                          ? latestRecord['bpStatus']
                          : "No Data",
                      lastUpdated: lastUpdatedTime,
                      icon: Icons.bloodtype,
                    ),
                  ],
                ),
                const SizedBox(height: 25),

                // Graph Analytics Section
                const Text(
                  "Graph Analytics",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                _buildGraphSection(docs),

                _buildLiveMiniAuditLogs(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required String status,
    required String lastUpdated,
    required IconData icon,
  }) {
    Color statusColor = _getStatusColor(status);
    if (status == "No Data") statusColor = Colors.grey;

    return Container(
      width: (MediaQuery.of(context).size.width - 50) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: statusColor, size: 20),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            lastUpdated,
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphSection(List<QueryDocumentSnapshot> docs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ["Daily", "Weekly", "Monthly"].map((tab) {
              bool isSelected = selectedGraphTab == tab;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedGraphTab = tab;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFC840E9)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tab,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black54,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 25),
          _buildMedicalChart(docs, selectedGraphTab, isHR: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          _buildMedicalChart(docs, selectedGraphTab, isHR: false),
        ],
      ),
    );
  }

  Widget _buildMedicalChart(
    List<QueryDocumentSnapshot> allDocs,
    String type, {
    required bool isHR,
  }) {
    // Process Data based on type
    DateTime now = DateTime.now();
    List<Map<String, dynamic>> filtered = [];

    for (var doc in allDocs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      Timestamp? ts = data['timestamp'];
      if (ts == null) continue;
      DateTime d = ts.toDate();

      if (type == "Daily" &&
          d.day == now.day &&
          d.month == now.month &&
          d.year == now.year) {
        filtered.add({...data, 'label': data['time']});
      } else if (type == "Weekly" && now.difference(d).inDays <= 7) {
        filtered.add({...data, 'label': DateFormat('E').format(d)});
      } else if (type == "Monthly" &&
          d.month == now.month &&
          d.year == now.year) {
        filtered.add({...data, 'label': "${d.day}/${d.month}"});
      }
    }

    // Limit to display points to prevent overflow and maintain clean look (max 7 points)
    if (filtered.length > 7) {
      filtered = filtered.sublist(0, 7);
    }
    filtered = filtered.reversed
        .toList(); // Chronological order for graph left to right

    if (filtered.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isHR ? "Heart Rate (BPM)" : "Blood Pressure (Systolic)",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 50),
          const Center(
            child: Text(
              "No data for this period",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 50),
        ],
      );
    }

    // Calculate Average
    double total = 0;
    for (var d in filtered) {
      total += isHR
          ? (d['heartRate'] as int).toDouble()
          : (d['systolic'] as int).toDouble();
    }
    int average = (total / filtered.length).round();

    // Prepare data for painter
    List<double> values = filtered
        .map(
          (d) => isHR
              ? (d['heartRate'] as int).toDouble()
              : (d['systolic'] as int).toDouble(),
        )
        .toList();
    List<String> labels = filtered.map((d) => d['label'].toString()).toList();
    List<Color> colors = filtered
        .map((d) => _getStatusColor(isHR ? d['hrStatus'] : d['bpStatus']))
        .toList();

    // Graph bounds
    double maxVal = isHR ? 160.0 : 200.0;
    double minVal = isHR ? 30.0 : 60.0;

    // Generate Y-Axis labels dynamically based on min/max
    List<int> yLabels = [];
    int step = ((maxVal - minVal) / 4).round();
    for (int i = 4; i >= 0; i--) {
      yLabels.add((minVal + (step * i)).round());
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(
          0xFFFAFAFC,
        ), // Very light grey background like the image
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section mirroring the image
          Text(
            isHR ? "Heart Rate Trend" : "Systolic BP Trend",
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$average",
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  isHR ? "BPM" : "mmHg",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  "AVERAGE",
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Chart Layout (Y-axis + Canvas + X-axis)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Y-Axis
              SizedBox(
                height: 140, // Match canvas height
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: yLabels
                      .map(
                        (l) => Text(
                          "$l",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(width: 15),
              // Chart & X-Axis
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 140,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: MedicalGraphPainter(
                          values: values,
                          colors: colors,
                          maxValue: maxVal,
                          minValue: minVal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // X-Axis Labels
                    Row(
                      mainAxisAlignment: values.length > 1
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.center,
                      children: labels
                          .map(
                            (l) => SizedBox(
                              width:
                                  30, // Fixed width to center text under points
                              child: Text(
                                l,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==============================
// CUSTOM MEDICAL GRAPH PAINTER
// ==============================
class MedicalGraphPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double maxValue;
  final double minValue;

  MedicalGraphPainter({
    required this.values,
    required this.colors,
    required this.maxValue,
    required this.minValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double usableHeight = size.height;
    // Calculate distance between points
    final double pointSpacing = values.length > 1
        ? size.width / (values.length - 1)
        : size.width / 2;

    // 1. Draw Horizontal Grid Lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      double y = usableHeight - (usableHeight * (i / 4));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // List to store calculated points for the line later
    List<Offset> points = [];

    // 2. Draw Vertical Drops (Bars)
    final double barWidth = 6.0;
    for (int i = 0; i < values.length; i++) {
      double x = values.length > 1 ? i * pointSpacing : size.width / 2;
      double normalizedY = (values[i] - minValue) / (maxValue - minValue);
      normalizedY = normalizedY.clamp(0.0, 1.0);
      double y = usableHeight - (usableHeight * normalizedY);

      points.add(Offset(x, y));

      final barPaint = Paint()
        ..color = colors[i]
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      // Draw line from bottom to the data point
      canvas.drawLine(Offset(x, usableHeight), Offset(x, y), barPaint);
    }

    // 3. Draw Connecting Line (Purple)
    if (points.length > 1) {
      final path = Path();
      final linePaint = Paint()
        ..color =
            const Color(0xFFC840E9) // Medical Purple
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 4. Draw Data Points (White circles with Purple border)
    final circleFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final circleStroke = Paint()
      ..color = const Color(0xFFC840E9)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (Offset point in points) {
      canvas.drawCircle(point, 4.5, circleFill);
      canvas.drawCircle(point, 4.5, circleStroke);
    }
  }

  @override
  bool shouldRepaint(covariant MedicalGraphPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

// ==============================
// ADD HEALTH DATA PAGE (MANUAL ENTRY)
// ==============================
class AddHealthDataPage extends StatefulWidget {
  final String patientName;
  const AddHealthDataPage({super.key, required this.patientName});

  @override
  State<AddHealthDataPage> createState() => _AddHealthDataPageState();
}

class _AddHealthDataPageState extends State<AddHealthDataPage> {
  final _formKey = GlobalKey<FormState>();
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  final TextEditingController _hrController = TextEditingController();
  final TextEditingController _sysController = TextEditingController();
  final TextEditingController _diaController = TextEditingController();
  bool _isLoading = false;

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          selectedDate.hour,
          selectedDate.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (picked != null) {
      setState(() {
        selectedTime = picked;
        selectedDate = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  Map<String, dynamic> evaluateHeartRate(int hr) {
    if (hr > 120) {
      return {
        'status': 'Critical',
        'msg':
            'Your heart rate is critically high. Please visit the nearest hospital immediately.',
      };
    } else if (hr >= 101) {
      return {
        'status': 'Warning',
        'msg':
            'Your heart rate is higher than normal. Please monitor your condition carefully.',
      };
    } else if (hr < 50) {
      return {
        'status': 'Critical',
        'msg':
            'Your heart rate is critically low. Please seek medical attention immediately.',
      };
    } else if (hr < 60) {
      return {
        'status': 'Low',
        'msg': 'Your heart rate is lower than normal. Please monitor.',
      };
    }
    return {'status': 'Normal', 'msg': 'Heart rate is normal.'};
  }

  Map<String, dynamic> evaluateBloodPressure(int sys, int dia) {
    if (sys > 140 || dia > 90) {
      return {
        'status': 'Critical',
        'msg':
            'Your blood pressure is dangerously high. Please visit a hospital immediately.',
      };
    } else if (sys > 120 || dia > 80) {
      return {
        'status': 'Warning',
        'msg':
            'Your blood pressure is above normal. Please monitor your health carefully.',
      };
    } else if (sys < 90 || dia < 60) {
      return {
        'status': 'Critical',
        'msg':
            'Your blood pressure is too low. Please seek medical attention immediately.',
      };
    }
    return {'status': 'Normal', 'msg': 'Blood pressure is normal.'};
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    int hr = int.parse(_hrController.text.trim());
    int sys = int.parse(_sysController.text.trim());
    int dia = int.parse(_diaController.text.trim());

    Map<String, dynamic> hrEval = evaluateHeartRate(hr);
    Map<String, dynamic> bpEval = evaluateBloodPressure(sys, dia);

    // Combine notifications
    List<String> msgs = [];
    if (hrEval['status'] != 'Normal') msgs.add(hrEval['msg']);
    if (bpEval['status'] != 'Normal') msgs.add(bpEval['msg']);
    String combinedNotification = msgs.join("\n\n");

    try {
      await FirebaseFirestore.instance.collection('health_records').add({
        'patientName': widget.patientName,
        'timestamp': Timestamp.fromDate(selectedDate),
        'day': DateFormat('EEEE').format(selectedDate),
        'date': DateFormat('dd/MM/yyyy').format(selectedDate),
        'time': selectedTime.format(context),
        'heartRate': hr,
        'systolic': sys,
        'diastolic': dia,
        'hrStatus': hrEval['status'],
        'bpStatus': bpEval['status'],
        'notification': combinedNotification,
      });

      // Log action securely
      String encryptedAction = await SecurityService.encryptData(
        "Added manual health record for ${widget.patientName}",
      );
      await FirebaseFirestore.instance.collection('audit_logs').add({
        'user': await SecurityService.encryptData(widget.patientName),
        'action': encryptedAction,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Health Record Saved Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to save data"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Health Data")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Date & Time",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        DateFormat('EEEE, dd/MM/yyyy').format(selectedDate),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time),
                      label: Text(selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              const Text(
                "Heart Rate (BPM)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _hrController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "e.g. 78",
                  suffixText: "BPM",
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? "Enter Heart Rate" : null,
              ),
              const SizedBox(height: 25),

              const Text(
                "Blood Pressure (mmHg)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sysController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Systolic",
                        hintText: "e.g. 120",
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Required" : null,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text("/", style: TextStyle(fontSize: 24)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _diaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: "Diastolic",
                        hintText: "e.g. 80",
                      ),
                      validator: (val) =>
                          val == null || val.isEmpty ? "Required" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: _saveData,
                      child: const Text(
                        "Save Record",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================
// HEALTH HISTORY PAGE
// ==============================
class HealthHistoryPage extends StatelessWidget {
  final String patientName;
  const HealthHistoryPage({super.key, required this.patientName});

  Color _getStatusColor(String status) {
    if (status == 'Critical') return Colors.red;
    if (status == 'Warning' || status == 'Low') return Colors.amber;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Health History")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('health_records')
            .where('patientName', isEqualTo: patientName)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No records found."));
          }

          List<QueryDocumentSnapshot> docs = snapshot.data!.docs.toList();
          docs.sort((a, b) {
            Timestamp tA = a['timestamp'];
            Timestamp tB = b['timestamp'];
            return tB.compareTo(tA);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              Map<String, dynamic> data =
                  docs[index].data() as Map<String, dynamic>;

              Color hrColor = _getStatusColor(data['hrStatus']);
              Color bpColor = _getStatusColor(data['bpStatus']);

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${data['day']}, ${data['date']}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            data['time'],
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildHistoryStat(
                            "Heart Rate",
                            "${data['heartRate']} BPM",
                            data['hrStatus'],
                            hrColor,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.grey.shade300,
                          ),
                          _buildHistoryStat(
                            "Blood Pressure",
                            "${data['systolic']}/${data['diastolic']}",
                            data['bpStatus'],
                            bpColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHistoryStat(
    String title,
    String value,
    String status,
    Color color,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
