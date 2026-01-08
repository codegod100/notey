---
name: roc-zulip
description: Read messages from the Roc Zulip chat at roc.zulipchat.com
---

# Roc Zulip Chat Skill

Read messages from the Roc Zulip chat at https://roc.zulipchat.com/

## Configuration

Uses credentials from `~/zuliprc`:
```ini
[api]
email=your-email@example.com
key=your-api-key
site=https://roc.zulipchat.com
```

## Commands

### List streams
```bash
EMAIL=$(grep "^email=" ~/zuliprc | cut -d= -f2)
KEY=$(grep "^key=" ~/zuliprc | cut -d= -f2)
curl -s -u "$EMAIL:$KEY" "https://roc.zulipchat.com/api/v1/streams" | jq '.streams[] | {name, description}'
```

### Get recent messages from a stream
```bash
EMAIL=$(grep "^email=" ~/zuliprc | cut -d= -f2)
KEY=$(grep "^key=" ~/zuliprc | cut -d= -f2)
STREAM="beginners"  # change to desired stream
curl -s -u "$EMAIL:$KEY" "https://roc.zulipchat.com/api/v1/messages?anchor=newest&num_before=20&num_after=0&narrow=%5B%7B%22operator%22%3A%22stream%22%2C%22operand%22%3A%22$STREAM%22%7D%5D" | jq '.messages[] | {sender: .sender_full_name, subject, content}'
```

### Get messages from a specific topic
```bash
EMAIL=$(grep "^email=" ~/zuliprc | cut -d= -f2)
KEY=$(grep "^key=" ~/zuliprc | cut -d= -f2)
STREAM="beginners"
TOPIC="my topic"
curl -s -u "$EMAIL:$KEY" "https://roc.zulipchat.com/api/v1/messages?anchor=newest&num_before=20&num_after=0&narrow=%5B%7B%22operator%22%3A%22stream%22%2C%22operand%22%3A%22$STREAM%22%7D%2C%7B%22operator%22%3A%22topic%22%2C%22operand%22%3A%22$TOPIC%22%7D%5D" | jq '.messages[] | {sender: .sender_full_name, content}'
```

### Search messages
```bash
EMAIL=$(grep "^email=" ~/zuliprc | cut -d= -f2)
KEY=$(grep "^key=" ~/zuliprc | cut -d= -f2)
QUERY="your search term"
curl -s -u "$EMAIL:$KEY" "https://roc.zulipchat.com/api/v1/messages?anchor=newest&num_before=50&num_after=0&narrow=%5B%7B%22operator%22%3A%22search%22%2C%22operand%22%3A%22$QUERY%22%7D%5D" | jq '.messages[] | {stream: .display_recipient, subject, sender: .sender_full_name, content}'
```

### Get topics in a stream
```bash
EMAIL=$(grep "^email=" ~/zuliprc | cut -d= -f2)
KEY=$(grep "^key=" ~/zuliprc | cut -d= -f2)
STREAM_ID=231634  # get stream_id from list streams
curl -s -u "$EMAIL:$KEY" "https://roc.zulipchat.com/api/v1/users/me/$STREAM_ID/topics" | jq '.topics[] | .name'
```

## Common Streams

- `beginners` - Questions from people learning Roc
- `ideas` - Ideas for Roc projects or Roc itself  
- `compiler development` - Compiler internals discussion
- `platform development` - Platform development discussion
- `show and tell` - Share things you've done with Roc
- `announcements` - Official announcements
- `off topic` - Non-Roc discussion

## Usage Notes

- Increase `num_before` to get more messages (max 5000)
- Use `anchor=oldest` and `num_after` to get oldest messages first
- The `content` field contains the message in HTML format
