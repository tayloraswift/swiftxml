# SwiftXML

[![Build](https://travis-ci.org/kelvin13/swiftxml.svg?branch=master)](https://travis-ci.org/kelvin13/swiftxml)
[![Issues](https://img.shields.io/github/issues/kelvin13/swiftxml.svg)](https://github.com/kelvin13/swiftxml/issues?state=open)
[![Language](https://img.shields.io/badge/version-swift_4-ffa020.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/license-GPL3-ff3079.svg)](https://github.com/kelvin13/swiftxml/blob/master/LICENSE.gpl3)
[![Queen](https://img.shields.io/badge/taylor-swift-e030ff.svg)](https://www.google.com/search?q=where+is+ts6&oq=where+is+ts6)

**Lightweight XML parsing in *pure* Swift 4. No Foundation. No dependencies.**

SwiftXML doesn’t wrap anything. It parses XML directly, character by character. And the API is simple and easy to use:

```swift
protocol XMLParser
{
    mutating
    func handle_data(data:[Unicode.Scalar])
    mutating
    func handle_tag_start(name:String, attributes:[String: String])
    mutating
    func handle_tag_empty(name:String, attributes:[String: String])
    mutating
    func handle_tag_end(name:String)
    mutating
    func handle_processing_instruction(target:String, data:[Unicode.Scalar])
    mutating
    func handle_error(_ message:String, line:Int, column:Int)
}

extension XMLParser
{
    mutating
    func parse(_ str:String)

    mutating
    func parse(path:String)
}
```

Import the package with 
```swift
import XML
```

Supported XML features:

- [x] parse start, empty, and end tags, and XML data
- [x] unescape XML default entity references (`&lt;`, `&gt;`, `&apos;`, `&quot;`, `&amp;`) in text data
- [x] unescape XML default entity references (`&lt;`, `&gt;`, `&apos;`, `&quot;`, `&amp;`) in attribute data
- [x] unescape XML character references in text data
- [x] unescape XML character references in attribute data
- [x] parse XML processing instructions
- [x] parse XML comments
- [ ] expose XML comments
- [ ] parse XML `CDATA` sections 
- [ ] parse XML entity declarations 
- [ ] parse XML element type declarations 
- [ ] parse XML attribute list declarations 
- [ ] parse and validate XML namespaces
- [x] expose syntax error line and column numbers

SwiftXML will tokenize your XML string into tags and data. It does not build any tree structures.

See the [`tests.swift`](tests/swiftxml/tests.swift) file for a usage example.
