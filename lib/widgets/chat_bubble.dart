import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_model.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  
  const ChatBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser 
          ? Alignment.centerRight 
          : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: message.isUser 
              ? Colors. blue. shade700 
              : const Color(0xFF2D2D2D), // Замість shade850
          borderRadius: BorderRadius. only(
            topLeft: const Radius.circular(18),
            topRight: const Radius. circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black. withValues(alpha: 0.2), // Замість withOpacity
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            message.isUser
                ? Text(
                    message.content,
                    style: const TextStyle(
                      color: Colors. white,
                      fontSize: 15,
                    ),
                  )
                : MarkdownBody(
                    data: _preprocessMarkdown(message. content),
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        Clipboard.setData(ClipboardData(text: href));
                        ScaffoldMessenger. of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard')),
                        );
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                      h1: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      h2: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      h3: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      em: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                      listBullet: const TextStyle(color: Colors.white),
                      code: TextStyle(
                        backgroundColor: Colors.grey. shade900,
                        color: Colors.greenAccent. shade200,
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.grey. shade900,
                        borderRadius: BorderRadius. circular(8),
                        border: Border.all(color: Colors. grey.shade700),
                      ),
                      codeblockPadding: const EdgeInsets.all(12),
                      blockquote: const TextStyle(color: Colors.grey, fontStyle: FontStyle. italic),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.blue. shade400, width: 3),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.only(left: 12),
                      tableHead: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      tableBody: const TextStyle(color: Colors.white),
                      tableBorder: TableBorder.all(color: Colors.grey. shade600),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.grey.shade600)),
                      ),
                    ),
                  ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize. min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
                if (! message.isUser) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    child: Icon(
                      Icons.copy,
                      size: 14,
                      color: Colors.grey. shade500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _preprocessMarkdown(String content) {
    String processed = content;
    
    processed = processed.replaceAllMapped(
      RegExp(r'^(\s*)\* ', multiLine: true),
      (match) => '${match.group(1)}• ',
    );
    
    return processed;
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour. toString().padLeft(2, '0')}:${time. minute.toString().padLeft(2, '0')}';
  }
}