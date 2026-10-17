# The AI helper (Ablobo)

Settings → **AI helper** answers questions about using Ablox: making a room,
playing with friends, coins, the closet, Studio, controls, problems. Added in
7.9 from the suggestion box. The same helper is in the web version
(Settings → AI helper).

## How a question is answered

1. **Checked on the iPad first** (`AIHelper.check`): empty, too long (300
   characters), anything that looks personal — eight or more digits, an email
   address, a "1-2-3" street number, the words for address or phone number —
   and anything the chat filter would hide are not sent. The child is asked to
   rephrase.
2. **The help list** (`HelpFAQ`, 22 answers in English and Japanese) answers
   by keywords. A confident match is shown at once and never reaches the
   network or the day's count. The six buttons under the box all have answers
   here.
3. **The AI**, only when a grown-up has switched it on in Family settings *and*
   saved a key there. The request is OpenAI-compatible chat completions to Groq
   with `qwen/qwen3.8-27b` (Groq retired its Llama models in October 2026; when a model answers 404 the next of `openai/gpt-oss-20b`, `openai/gpt-oss-120b`, `llama-3.1-8b-instant` is tried, then a chat model is picked from the account's own `/models` list, and the one that answered is tried first next time): a short guide as the
   system prompt (under 1,600 characters), the last two turns, the question,
   `max_tokens` 400, temperature 0.3. The answer goes through the chat filter;
   Markdown and links are taken out.

If the AI cannot be reached, the key is refused or the day's questions are
used up, the help list's best answer is shown instead.

## For grown-ups (Family settings → AI helper)

- **Use the AI** — off until switched on.
- **Questions a day** — 5, 10, 20 (the default) or 50. The help list never
  counts. There are a few seconds between two questions.
- **API key** — a key from <https://console.groq.com> (free tier). It is kept
  in the iPad's keychain (`Net/AIHelperClient.swift`, account
  `ai-helper-key`), in the browser's own storage on the web, and is sent only
  in the `Authorization` header to the provider. It is never written to a
  file, a world, a save, a message or this repository. **Remove key** deletes
  it.

Family settings are behind the family passcode, so a child cannot turn the AI
on or change the key.

## Keys sent in the suggestion box

A suggestion asked for the AI and included a key in the message. That key was
**not** used and is not in the app or the repository: each family types their
own. A key that has been written in a message should be treated as seen by
others — delete it at console.groq.com and make a new one.

## Code

| | |
|---|---|
| `AbloxCore/AIHelper.swift` | checks, the guide, the request, reading the answer, the day's count, the help list (tested in `AIHelperTests`) |
| `Net/AIHelperClient.swift` | the keychain entry and the one request |
| `UI/MainMenu/AIHelperViews.swift` | the Settings card, the conversation, the Family section |
| `AbloxGames/web/src/app/aihelper.ts` | the web version (tested in `web/test/aihelper.test.ts`) |
