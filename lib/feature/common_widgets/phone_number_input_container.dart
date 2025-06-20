import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class PhoneInputContainer extends StatefulWidget {
  final Function(String raw, String complete) onChanged;

  const PhoneInputContainer({
    Key? key,
    required this.onChanged,
  }) : super(key: key);

  @override
  _PhoneInputContainerState createState() => _PhoneInputContainerState();
}

class _PhoneInputContainerState extends State<PhoneInputContainer> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SizedBox(
        height: 60,
        child: IntlPhoneField(
          initialCountryCode: 'IN',
          showCountryFlag: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ], // allow only digits
          showDropdownIcon: true,
          dropdownIcon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.grey,
            size: 24,
          ),
          invalidNumberMessage: '',

          // Force vertical centering of both hint and typed text:
          textAlignVertical: TextAlignVertical.center,

          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: 'Enter phone number',
            hintStyle: const TextStyle(
              color: Colors.grey,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
            // Remove vertical padding entirely; centering is handled by textAlignVertical
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            counterText: '',
          ),

          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            height: 1.0, // no extra line-height padding
          ),

          dropdownTextStyle: const TextStyle(
            color: Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),

          onChanged: (phone) {
            widget.onChanged(phone.number, phone.completeNumber);
          },
        ),
      ),
    );
  }
}
