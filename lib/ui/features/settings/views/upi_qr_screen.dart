import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/app_theme.dart';
import '../../../../data/repositories/shop_repository.dart';

class UpiQrScreen extends StatefulWidget {
  final double? initialAmount;
  final String? invoiceNo;
  final String? customerName;
  final int? autoCloseSeconds;

  const UpiQrScreen({
    super.key,
    this.initialAmount,
    this.invoiceNo,
    this.customerName,
    this.autoCloseSeconds,
  });

  @override
  State<UpiQrScreen> createState() => _UpiQrScreenState();
}

class _UpiQrScreenState extends State<UpiQrScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _amountController = TextEditingController();
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  Timer? _autoCloseTimer;
  int _remainingSeconds = 0;

  String _amount = '';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _animController.forward();

    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amount = widget.initialAmount!.toStringAsFixed(
        widget.initialAmount! == widget.initialAmount!.roundToDouble() ? 0 : 2,
      );
      _amountController.text = _amount;
    }

    if (widget.autoCloseSeconds != null && widget.autoCloseSeconds! > 0) {
      _remainingSeconds = widget.autoCloseSeconds!;
      _autoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds <= 1) {
          timer.cancel();
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else {
          if (mounted) {
            setState(() => _remainingSeconds--);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _amountController.dispose();
    _animController.dispose();
    super.dispose();
  }

  String _buildUpiUri(String upiId, String name, String amount) {
    final encodedName = Uri.encodeComponent(name.isEmpty ? 'Perfect Solution' : name);
    if (amount.isEmpty || amount == '0') {
      return 'upi://pay?pa=$upiId&pn=$encodedName&cu=INR';
    }
    return 'upi://pay?pa=$upiId&pn=$encodedName&am=$amount&cu=INR';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ShopRepository>();
    final activeUpiId = repo.getActiveUpiId();
    final namesMap = repo.getUpiNamesMap();
    final refName = (activeUpiId != null ? namesMap[activeUpiId] : null) ?? '';
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    if (activeUpiId == null || activeUpiId.trim().isEmpty) {
      return isMobile
          ? Scaffold(
              backgroundColor: const Color(0xFF080D1A),
              body: SafeArea(child: _buildNoUpiWidget(context)),
            )
          : SizedBox(width: 440, child: _buildNoUpiWidget(context));
    }

    final upiUri = _buildUpiUri(activeUpiId, refName, _amount);
    final content = _buildQrContent(context, activeUpiId, refName, upiUri, isMobile);

    if (isMobile) {
      return Scaffold(
        backgroundColor: const Color(0xFF080D1A),
        body: SafeArea(child: content),
      );
    }
    return SizedBox(width: 440, child: content);
  }

  Widget _buildNoUpiWidget(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.warning, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Active UPI Configured',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            const Text(
              'Go to Settings > UPI Payment to add and activate a UPI ID.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Close'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: AppTheme.textPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrContent(
    BuildContext context,
    String upiId,
    String refName,
    String upiUri,
    bool isMobile,
  ) {
    final double qrSize = isMobile ? 220.0 : 240.0;

    return Stack(
      children: [
        Positioned(
          top: -60,
          left: -60,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [AppTheme.secondary.withValues(alpha: 0.14), Colors.transparent],
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            isMobile ? 20 : 28,
            isMobile ? 16 : 24,
            isMobile ? 20 : 28,
            isMobile ? 24 : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.secondary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UPI QR Pay',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          if (widget.invoiceNo != null && widget.invoiceNo!.isNotEmpty)
                            Text(
                              'Invoice: ${widget.invoiceNo}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.secondary, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (widget.autoCloseSeconds != null && widget.autoCloseSeconds! > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: AppTheme.warning),
                              const SizedBox(width: 4),
                              Text(
                                '${_remainingSeconds}s',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.warning),
                              ),
                            ],
                          ),
                        ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // UPI ID badge
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (refName.isNotEmpty) ...[
                      Text(refName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 3),
                    ],
                    if (widget.customerName != null && widget.customerName!.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.person_rounded, size: 12, color: AppTheme.primaryLight),
                          const SizedBox(width: 4),
                          Text(
                            'Customer: ${widget.customerName!}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryLight),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                    ],
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, size: 13, color: AppTheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(upiId,
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: upiId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('UPI ID copied!'),
                                backgroundColor: AppTheme.success,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(Icons.copy_rounded, size: 14, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Amount Display (Read-Only when amount is set, editable if standalone)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _amount.isNotEmpty
                        ? AppTheme.secondary.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 1.2,
                  ),
                ),
                child: widget.initialAmount != null && widget.initialAmount! > 0
                    ? Column(
                        children: [
                          const Text(
                            'AMOUNT TO PAY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMuted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${widget.initialAmount!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: isMobile ? 24 : 28,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary,
                            ),
                          ),
                        ],
                      )
                    : TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        onChanged: (val) => setState(() => _amount = val.trim()),
                        style: TextStyle(
                          fontSize: isMobile ? 22 : 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: 'Enter amount (optional)',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: AppTheme.textMuted.withValues(alpha: 0.6),
                          ),
                          prefixIcon: _amount.isNotEmpty
                              ? const Padding(
                                  padding: EdgeInsets.only(left: 16, top: 14, bottom: 14),
                                  child: Text(
                                    '₹',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.secondary,
                                    ),
                                  ),
                                )
                              : null,
                          prefixIconConstraints: const BoxConstraints(minWidth: 0),
                          suffixIcon: _amount.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppTheme.textMuted),
                                  onPressed: () {
                                    _amountController.clear();
                                    setState(() => _amount = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // QR Code
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.secondary.withValues(alpha: 0.32),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: upiUri,
                    version: QrVersions.auto,
                    size: qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0F19)),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B0F19)),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 13, color: AppTheme.textMuted),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Scan with GPay, PhonePe, Paytm or any UPI app',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
