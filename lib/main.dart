import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CashTrackerApp());
}

class CashTrackerApp extends StatelessWidget {
  const CashTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محافظ فودافون كاش',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE60000), // أحمر فودافون
          primary: const Color(0xFFE60000),
          secondary: const Color(0xFF222222),
          background: const Color(0xFFF8F9FA),
        ),
        fontFamily: 'Roboto',
      ),
      home: const DashboardScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// Database Helper (Sqflite)
// -----------------------------------------------------------------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vodafone_wallets.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE wallets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        initial_balance REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_id INTEGER NOT NULL,
        type TEXT NOT NULL, -- 'DEPOSIT' or 'WITHDRAWAL'
        amount REAL NOT NULL,
        fee REAL NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (wallet_id) REFERENCES wallets (id) ON DELETE CASCADE
      )
    ''');
  }

  // Wallets Operations
  Future<int> insertWallet(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('wallets', row);
  }

  Future<int> updateWallet(int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.update('wallets', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWallet(int id) async {
    final db = await instance.database;
    await db.delete('transactions', where: 'wallet_id = ?', whereArgs: [id]);
    return await db.delete('wallets', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getAllWalletsWithBalances() async {
    final db = await instance.database;
    final wallets = await db.query('wallets');
    List<Map<String, dynamic>> results = [];

    for (var wallet in wallets) {
      int id = wallet['id'] as int;
      double initial = (wallet['initial_balance'] as num).toDouble();

      final transRes = await db.rawQuery('''
        SELECT 
          SUM(CASE WHEN type = 'DEPOSIT' THEN amount ELSE 0 END) as total_deposit,
          SUM(CASE WHEN type = 'WITHDRAWAL' THEN amount ELSE 0 END) as total_withdrawal
        FROM transactions
        WHERE wallet_id = ?
      ''', [id]);

      double deposits = (transRes.first['total_deposit'] as num?)?.toDouble() ?? 0.0;
      double withdrawals = (transRes.first['total_withdrawal'] as num?)?.toDouble() ?? 0.0;

      double currentBalance = initial + deposits - withdrawals;

      results.add({
        ...wallet,
        'current_balance': currentBalance,
        'total_deposits': deposits,
        'total_withdrawals': withdrawals,
      });
    }

    return results;
  }

  // Transactions Operations
  Future<int> insertTransaction(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('transactions', row);
  }

  Future<List<Map<String, dynamic>>> getTransactionsForWallet(int walletId) async {
    final db = await instance.database;
    return await db.query(
      'transactions',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      orderBy: 'created_at DESC',
    );
  }

  Future<int> deleteTransaction(int transId) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [transId]);
  }
}

// -----------------------------------------------------------------------------
// Main Dashboard Screen
// -----------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _wallets = [];
  bool _isLoading = true;
  double _totalSystemBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _refreshWallets();
  }

  Future<void> _refreshWallets() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getAllWalletsWithBalances();
    double total = 0.0;
    for (var w in data) {
      total += (w['current_balance'] as double);
    }
    setState(() {
      _wallets = data;
      _totalSystemBalance = total;
      _isLoading = false;
    });
  }

  void _openWalletForm([Map<String, dynamic>? wallet]) {
    final isEdit = wallet != null;
    final nameController = TextEditingController(text: isEdit ? wallet['wallet_name'] : '');
    final phoneController = TextEditingController(text: isEdit ? wallet['phone_number'] : '');
    final initBalController = TextEditingController(
      text: isEdit ? wallet['initial_balance'].toString() : '0.0',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? 'تعديل بيانات المحفظة' : 'إضافة محفظة / خط جديد',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم المحفظة (مثلاً: خط المحل 1)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم التليفون',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: initBalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرصيد الافتتاحي (جنيه)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE60000),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                final phone = phoneController.text.trim();
                final initBal = double.tryParse(initBalController.text) ?? 0.0;

                if (name.isEmpty || phone.isEmpty) return;

                if (isEdit) {
                  await DatabaseHelper.instance.updateWallet(wallet['id'], {
                    'wallet_name': name,
                    'phone_number': phone,
                    'initial_balance': initBal,
                  });
                } else {
                  await DatabaseHelper.instance.insertWallet({
                    'wallet_name': name,
                    'phone_number': phone,
                    'initial_balance': initBal,
                  });
                }

                Navigator.pop(ctx);
                _refreshWallets();
              },
              child: Text(
                isEdit ? 'حفظ التعديلات' : 'إضافة المحفظة',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة محافظ فودافون كاش', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFE60000),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Global Summary Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'إجمالي الفلوس في جميع المحافظ',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_totalSystemBalance.toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _wallets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey),
                              const SizedBox(height: 10),
                              const Text('لا توجد محافظ مسجلة حالياً'),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () => _openWalletForm(),
                                child: const Text('أضف أول رقم الآن'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _wallets.length,
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          itemBuilder: (context, index) {
                            final w = _wallets[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE60000),
                                  child: Icon(Icons.phone_android, color: Colors.white),
                                ),
                                title: Text(
                                  w['wallet_name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Text('رقم: ${w['phone_number']}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text('الرصيد الحالي', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(
                                      '${(w['current_balance'] as double).toStringAsFixed(2)} ج.م',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (ctx) => WalletDetailsScreen(wallet: w),
                                    ),
                                  );
                                  _refreshWallets();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFE60000),
        onPressed: () => _openWalletForm(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('إضافة رقم', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Wallet Details & Transactions Log Screen
// -----------------------------------------------------------------------------
class WalletDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> wallet;

  const WalletDetailsScreen({super.key, required this.wallet});

  @override
  State<WalletDetailsScreen> createState() => _WalletDetailsScreenState();
}

class _WalletDetailsScreenState extends State<WalletDetailsScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getTransactionsForWallet(widget.wallet['id']);
    setState(() {
      _transactions = data;
      _isLoading = false;
    });
  }

  void _openAddTransactionDialog() {
    final amountController = TextEditingController();
    final feeController = TextEditingController(text: '0');
    final notesController = TextEditingController();
    String type = 'DEPOSIT';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسجيل حركة جديدة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('إيداع (+)')),
                      selected: type == 'DEPOSIT',
                      selectedColor: Colors.green.shade100,
                      onSelected: (val) {
                        if (val) setModalState(() => type = 'DEPOSIT');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('سحب (-)')),
                      selected: type == 'WITHDRAWAL',
                      selectedColor: Colors.red.shade100,
                      onSelected: (val) {
                        if (val) setModalState(() => type = 'WITHDRAWAL');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'المبلغ (جنيه)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'العمولة / المصاريف (جنيه)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (مثلاً: اسم العميل)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: type == 'DEPOSIT' ? Colors.green : Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  final fee = double.tryParse(feeController.text) ?? 0.0;
                  final notes = notesController.text.trim();

                  if (amount <= 0) return;

                  await DatabaseHelper.instance.insertTransaction({
                    'wallet_id': widget.wallet['id'],
                    'type': type,
                    'amount': amount,
                    'fee': fee,
                    'notes': notes,
                    'created_at': DateTime.now().toIso8601String(),
                  });

                  Navigator.pop(ctx);
                  _loadTransactions();
                },
                child: const Text('حفظ الحركة', style: TextStyle(color: Colors.white, fontSize: 16)),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wallet['wallet_name']),
        backgroundColor: const Color(0xFFE60000),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف المحفظة'),
                  content: const Text('هل أنت أؤكد حذف هذه المحفظة وجميع حركاتها؟'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (confirm == true) {
                await DatabaseHelper.instance.deleteWallet(widget.wallet['id']);
                Navigator.pop(context);
              }
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('لا توجد حركات مسجلة لهذا الرقم حتى الآن'))
                      : ListView.builder(
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final t = _transactions[index];
                            final isDeposit = t['type'] == 'DEPOSIT';
                            final dt = DateTime.tryParse(t['created_at']) ?? DateTime.now();

                            return Dismissible(
                              key: Key(t['id'].toString()),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (dir) async {
                                await DatabaseHelper.instance.deleteTransaction(t['id']);
                                _loadTransactions();
                              },
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDeposit ? Colors.green.shade100 : Colors.red.shade100,
                                  child: Icon(
                                    isDeposit ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: isDeposit ? Colors.green : Colors.red,
                                  ),
                                ),
                                title: Text(
                                  '${isDeposit ? 'إيداع' : 'سحب'}: ${t['amount']} جنيه',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  '${dt.hour}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}/${dt.year}'
                                  '${t['notes'] != null && t['notes'].isNotEmpty ? ' | ${t['notes']}' : ''}',
                                ),
                                trailing: t['fee'] > 0
                                    ? Text('عمولة: ${t['fee']}ج', style: const TextStyle(color: Colors.grey, fontSize: 12))
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE60000),
        onPressed: _openAddTransactionDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
