<!-- Generated distribution; edit the canonical repository. -->
# swift-ai-moonshotai 1.3.0

Independent Swift-native port of Vercel AI SDK. Source and upstream dispositions are in PROVENANCE.json and Porting/.

## Distribution manifest

Add this package to your SwiftPM dependencies:

```swift
.package(url: "https://github.com/SwiftAISDK/swift-ai-moonshotai.git", from: "1.3.0")
```

Products: `SwiftAIMoonshotAI`.
Contribute and report issues in the canonical SwiftAISDK repository.

## Authored usage guide

# Moonshot AI (Kimi) for Swift

`SwiftAIMoonshotAI` adds Moonshot AI (Kimi) to [SwiftAISDK](https://github.com/SwiftAISDK/SwiftAISDK), an independent Swift port of the Vercel AI SDK. It ports `@ai-sdk/moonshotai` and supports text generation.

Provider guide with models, options, streaming and errors:

- [Moonshot AI (Kimi)](https://swiftaisdk.github.io/SwiftAISDK/providers/moonshotai/)

## Usage

Add the `SwiftAI` product from `swift-ai-core` and the `SwiftAIMoonshotAI` product from this package to your target, then create the provider:

```swift
import SwiftAI
import SwiftAIMoonshotAI

let provider = try AIProviders.moonshotAI(configuration: MoonshotAIProviderSettings())
```

By default the provider reads `MOONSHOT_API_KEY` from the environment; values set in `MoonshotAIProviderSettings` take precedence.

To use every provider through one dependency, add the complete [SwiftAISDK](https://github.com/SwiftAISDK/SwiftAISDK) package instead; see [Install](https://swiftaisdk.github.io/SwiftAISDK/getting-started/install/).

## Contributing

This package is exported from `Packages/swift-ai-moonshotai` in the canonical [SwiftAISDK](https://github.com/SwiftAISDK/SwiftAISDK) repository. Open issues and pull requests there.
