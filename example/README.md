# mubeen_flutter example

A manual test harness for the `mubeen_flutter` plugin. It configures the plugin from a
button, so you can try different keys and options without restarting the app. It is not a
reference integration: for how to wire the plugin into your own app, follow the quick start
in the top-level README.

## Run it

```sh
cd example
flutter run
```

Enter an API key of type `public - JS client side`, then tap configure. The other buttons
call each plugin method and log the result on screen.

- iOS needs a device or simulator on iOS 15.0 or newer.
- Optional: `flutter run --dart-define=MUBEEN_BUILD_ID=<id>` shows that id on screen, which
  helps tell builds apart.

Integration tests and the Swift `RunnerTests` are not included in this package, so
Xcode's Product > Test will not work for the example project.
