# Biscuit Builder

A hands-free voice assistant for learning a menu. Press the button on your headset, ask a question out loud, and hear a short answer in your ear. Answers come only from your own info, never from Claude's guesses. There's also a quiz tab for practicing.

I built it with Claude to learn the menu at my job as a cook in Charleston, WV. The story, a demo, and a full technical walkthrough are at **[biscuitbuilder.com](https://biscuitbuilder.com)**.

**This copy uses a made-up sample diner menu and placeholder photos.** The real restaurant's menu and photos aren't included. Swap in your own info.

## How it works

Headset click → Apple speech recognition (on the phone) → text → Claude API (Haiku) with your info → short text answer + a hidden `ITEM:` line → the phone speaks the answer and shows a card for that item.

- Claude only hears text, never audio.
- The API has no memory, so your full instructions are sent with every question, plus the last question and answer for follow-ups. Follow-ups are forgotten after 90 seconds.
- Claude ends every reply with a hidden line like `ITEM: Hilltop`. The app removes it before speaking and uses it to pick the card. Cards are drawn from the app's own data, never from Claude's wording.
- About $0.0004 per question on Haiku.

## Make it yours

- `MenuData.swift`: your info, as data. Edit the items here.
- `Menu.swift`: Claude's instructions: answer rules, examples, sound-alike words, speech hints. When you change a rule, change the examples too.
- `Assets.xcassets`: photos for the Picture quiz, named `photo-<item-name>`.
- `Quiz.swift`, `BuildGrader.swift`, `VoiceQuiz.swift`: the quiz has some menu-specific bits (meats, gravy amounts, fryer buttons). Adjust them to fit your info.

Everything else (speech, the headset button, the Claude request, the listen → ask → speak loop) doesn't care what the info is.

## Run it

You need a Mac with Xcode, an iPhone on iOS 18 or later, and an Anthropic API key with a few dollars of credit.

1. Open `BiscuitVoice.xcodeproj` in Xcode.
2. Paste your API key into `BiscuitVoice/Secrets.swift`. **Never commit or share that file once your key is in it.**
3. In Signing & Capabilities, pick your own team and change the bundle identifier.
4. Plug in your iPhone, pick it as the run destination, and press ▶.

With a free Apple account, the app has to be reinstalled every 7 days.

## File map

- `Assistant.swift`: listen → ask → speak, plus follow-up memory.
- `ClaudeClient.swift`: the request to the Messages API (Haiku, 150 max tokens, thinking off).
- `SpeechListener.swift`: mic and speech recognition. Stops on "over", a 1.3-second pause, a second click, or 10 seconds.
- `HeadsetButton.swift`: makes the headset button work like the big on-screen button.
- `Speaker.swift`, `VoicePicker.swift`, `OpenAIVoice.swift`: text-to-speech. Apple voice by default; optional OpenAI voice.
- `ContentView.swift`, `BuildCard.swift`: the Ask tab and the item card.
- `Quiz.swift`, `QuizView.swift`, `VoiceQuiz.swift`, `VoiceQuizView.swift`, `BuildGrader.swift`: the quiz.

## Want to build your own without this code?

There's a copy-and-paste prompt at [biscuitbuilder.com/build-your-own](https://biscuitbuilder.com/build-your-own) that walks you through building your own version with Claude, for whatever you're learning.

---

A personal project. Not affiliated with or endorsed by any restaurant.
