import 'package:flutter/material.dart';

class NavigationDrawer extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const NavigationDrawer({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.black,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors. black,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue. shade900,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.psychology,
                      size: 40,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Local LLM Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight. bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'by HATOP-OC',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildNavItem(
                    context,
                    index: 0,
                    title: 'Chats',
                    icon: Icons.chat_bubble_outline,
                  ),
                  _buildNavItem(
                    context,
                    index: 1,
                    title: 'Models',
                    icon: Icons.model_training,
                  ),
                  _buildNavItem(
                    context,
                    index: 2,
                    title: 'Settings',
                    icon: Icons.settings_outlined,
                  ),
                  _buildNavItem(
                    context,
                    index: 3,
                    title: 'About',
                    icon: Icons.info_outline,
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            Padding(
              padding: const EdgeInsets. all(16.0),
              child: Column(
                children: [
                  Text(
                    'v1.0.0',
                    style: TextStyle(color: Colors.grey. shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Developed by HATOP-OC',
                    style: TextStyle(
                      color: Colors.grey. shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isSelected = selectedIndex == index;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors. blue : Colors.white,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors. blue : Colors.white,
        ),
      ),
      tileColor: isSelected ? Colors.blue. withValues(alpha: 0.1) : null,
      onTap: () {
        onItemTapped(index);
        Navigator.pop(context);
      },
    );
  }
}