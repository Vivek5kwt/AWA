import 'dart:convert';
import 'package:awa/config/local_extension.dart';
import 'package:awa/core/network/http_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TransactionScreen extends StatefulWidget {
  final bool isDarkMode;
  final String email;

  const TransactionScreen({
    Key? key,
    required this.isDarkMode,
    required this.email,
  }) : super(key: key);

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(ApiConstants.getTransaction)
          .replace(queryParameters: {'email': widget.email});
      print('dsndsjdj $uri');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final txns = data['transactions'] as List? ?? [];
        setState(() {
          _transactions = txns.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load transactions. (${resp.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = widget.isDarkMode
        ? const [Color(0xFF181A20), Color(0xFF232526), Color(0xFF181A20)]
        : const [Color(0xFF0093E9), Color(0xFF80D0C7), Color(0xFFFCF6BA)];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.cyanAccent, Colors.blueAccent, Colors.white]
                : [Colors.deepPurple, Colors.indigo, Colors.amber],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(rect),
          child: Text(
            context.loc.myTransactions,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 1.1,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 5,
                  offset: Offset(1, 2),
                ),
              ],
            ),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: CircleAvatar(
            backgroundColor: widget.isDarkMode
                ? Colors.white.withOpacity(0.09)
                : Colors.blue.shade50.withOpacity(0.9),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: widget.isDarkMode ? Colors.white : Colors.black),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.1, 0.7, 1.0],
            ),
          ),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.1, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                _error!,
                style: TextStyle(
                    color: widget.isDarkMode ? Colors.red[200] : Colors.red,
                    fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          )
              : _transactions.isEmpty
              ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                "No transactions found yet.",
                style: TextStyle(
                  color: widget.isDarkMode ? Colors.white60 : Colors.black54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            itemCount: _transactions.length,
            itemBuilder: (context, idx) {
              final txn = _transactions[idx];
              return GlassyTransactionCard(
                txn: txn,
                isDarkMode: widget.isDarkMode,
              );
            },
          ),
        ),
      ),
    );
  }
}

class GlassyTransactionCard extends StatelessWidget {
  final Map<String, dynamic> txn;
  final bool isDarkMode;

  const GlassyTransactionCard({
    super.key,
    required this.txn,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    //final isSuccess = (txn['status']?.toString().toLowerCase() == 'success');
    final isSuccess = true;
    final iconColor = isSuccess
        ? Colors.greenAccent
        : txn['status']?.toString().toLowerCase() == 'pending'
        ? Colors.orangeAccent
        : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDarkMode
              ? [Colors.white.withOpacity(0.04), Colors.white.withOpacity(0.07)]
              : [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.96)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isSuccess
                ? Colors.greenAccent.withOpacity(0.18)
                : iconColor.withOpacity(0.16),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: iconColor.withOpacity(0.16),
          width: 1.7,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.15),
          child: Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: iconColor,
            size: 32,
          ),
        ),
        title: Text(
          txn['plan']?.toString() ?? "Plan",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 17,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date: ${txn['last_updated'] ?? "--"}',
              style: TextStyle(
                color: isDarkMode ? Colors.white60 : Colors.grey.shade700,
                fontSize: 13,
              ),
            ),

            Text(
              'Txn ID: ${txn['razorpay_payment_id'] ?? "--"}',
              style: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.grey.shade600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '₹${txn['amount'] ?? "--"}',
              style: TextStyle(
                color: isSuccess ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (txn['payment_mode'] != null)
              Text(
                txn['payment_mode'].toString().toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.white70 : Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }
}
