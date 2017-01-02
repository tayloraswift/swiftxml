# SwiftXML

[![Language](https://img.shields.io/badge/language-swift-ffa020.svg
)](https://developer.apple.com/swift)
[![Issues](https://img.shields.io/github/issues/kelvin13/swiftxml.svg
)](https://github.com/kelvin13/swiftxml/issues?state=open)
[![License](https://img.shields.io/badge/license-GPL3-ff3079.svg)](https://github.com/kelvin13/swiftxml/blob/master/LICENSE.gpl3)
[![Build](https://travis-ci.org/kelvin13/swiftxml.svg?branch=master)](https://travis-ci.org/kelvin13/swiftxml)
[![Queen](https://img.shields.io/badge/taylor-swift-e030ff.svg)](https://github.com/kelvin13/swiftxml)

**Lightweight XML parsing in *pure* Swift 3. No Foundation. No dependencies.**

SwiftXML exposes just two objects — a protocol and a function:

```swift
protocol Parser
{
    func handle_data(data:[UnicodeScalar])
    func handle_starttag(name:String, attributes:[String: String])
    func handle_startendtag(name:String, attributes:[String: String])
    func handle_endtag(name:String)
    func error(_:String, line:Int, column:Int)
}
```

```swift
func parse(_:String, parser:Parser)
```

SwiftXML will tokenize your XML string into tags and data. It does not build any tree structures; that is for you to implement. Nor does it read files from disk into memory; that is for the Swift standard library to implement (hint hint @ Swift standard library devs).

See the [swiftxmlTests.swift](https://github.com/kelvin13/swiftxml/blob/master/Tests/swiftxmlTests/swiftxmlTests.swift) file for a usage example, if you are still confused.
