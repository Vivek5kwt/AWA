import 'package:flutter/material.dart';

class CustomLanguageDropdown extends StatefulWidget {
  final bool isDarkMode;
  final String selectedLanguage;
  final String text;
  final List<String> languages;
  final ValueChanged<String> onChanged;

  const CustomLanguageDropdown({
    required this.isDarkMode,
    required this.selectedLanguage,
    required this.text,
    required this.languages,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  State<CustomLanguageDropdown> createState() => _CustomLanguageDropdownState();
}

class _CustomLanguageDropdownState extends State<CustomLanguageDropdown> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _arrowController;

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      duration: Duration(milliseconds: 260),
      vsync: this,
      lowerBound: 0,
      upperBound: 0.5,
      value: 0,
    );
  }

  @override
  void dispose() {
    _arrowController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _arrowController.forward();
    } else {
      _arrowController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = widget.isDarkMode ? Color(0xFF232526) : Colors.white;
    final iconColor = widget.isDarkMode ? Colors.white : Colors.black;
    final borderRadius = BorderRadius.circular(18);

    // Example language icons (use your own assets for more languages)
    final langIcons = {
      "English": Icons.language,
      "Hindi": Icons.g_translate,
      "Punjabi": Icons.translate,
      "Gujarati": Icons.translate,
      "Tamil": Icons.translate,
      "Marathi": Icons.translate,
      "Bengali": Icons.translate,
      "Urdu": Icons.translate,
      "Kannada": Icons.translate,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.text,
            style: theme.textTheme.titleMedium?.copyWith(
              color: iconColor,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        GestureDetector(
          onTap: _toggleDropdown,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 220),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              gradient: widget.isDarkMode
                  ? LinearGradient(
                colors: [Color(0xFF232526), Color(0xFF181A20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : LinearGradient(
                colors: [Color(0xFFe0eafc), Color(0xFFcfdef3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: borderRadius,
              boxShadow: [
                BoxShadow(
                  color: (widget.isDarkMode
                      ? Colors.blueGrey
                      : Colors.blueAccent)
                      .withOpacity(0.11),
                  blurRadius: 13,
                  offset: Offset(0, 3),
                )
              ],
              border: Border.all(
                color: widget.isDarkMode
                    ? Colors.white12
                    : Colors.blueGrey.withOpacity(0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Icon(langIcons[widget.selectedLanguage] ?? Icons.language, color: iconColor, size: 23),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.selectedLanguage,
                    style: TextStyle(
                      color: iconColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                RotationTransition(
                  turns: _arrowController,
                  child: Icon(Icons.keyboard_arrow_down, color: iconColor, size: 29),
                )
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 240),
          child: _isExpanded
              ? Container(
            margin: EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: bgColor.withOpacity(widget.isDarkMode ? 0.99 : 0.97),
              boxShadow: [
                BoxShadow(
                  color: (widget.isDarkMode ? Colors.black : Colors.blueGrey)
                      .withOpacity(0.13),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 320, // Show up to 5-6 languages, then scroll
                minHeight: 0,
              ),
              child: Scrollbar(
                thickness: 4,
                radius: Radius.circular(12),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: widget.languages.length,
                  itemBuilder: (context, index) {
                    final lang = widget.languages[index];
                    final isSelected = lang == widget.selectedLanguage;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: borderRadius,
                        onTap: () {
                          widget.onChanged(lang);
                          _toggleDropdown();
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 19, vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: borderRadius,
                            gradient: isSelected
                                ? LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.14),
                                Colors.orangeAccent.withOpacity(0.09),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(langIcons[lang] ?? Icons.language,
                                  color: isSelected
                                      ? Colors.amber[800]
                                      : iconColor,
                                  size: 22),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  lang,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.amber[800]
                                        : iconColor.withOpacity(0.85),
                                    fontWeight:
                                    isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 15.5,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: Colors.amber[700], size: 22)
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          )
              : SizedBox.shrink(),
        )
      ],
    );
  }
}

