@testable import swiftxmlTests

let test_cases:[(String, [Token])] =
[
("", []),
("data", [.data("data")]),
("<doc1>", [.open(name: "doc1", is_sc: false, attrs: [:])]),
("< doc2 >", [.open(name: "doc2", is_sc: false, attrs: [:])]),
("</doc3/>", [.error("invalid character '/' in tag 'doc3'", 0, 6), .error("invalid tag 'doc3' dropped", 0, 7)]),
("</doc4 >", [.close(name: "doc4")]),
("<doc5  /  >", [.open(name: "doc5", is_sc: true, attrs: [:])]),
("<0invalid >", [.error("invalid character '0' in tag ''", 0, 1), .error("invalid tag '' dropped", 0, 10)]),
("< // >", [.error("invalid character '/' in tag ''", 0, 3), .error("invalid tag '' dropped", 0, 5)]),
("</>", [.error("empty tag '</>' ignored", 0, 2)]),
("<", [.error("unexpected EOF", 0, 1)]),
("look! \n<> An empty tag!", [.data("look! \n"), .error("empty tag '<>' ignored", 1, 1), .data(" An empty tag!")]),
("the< doc6 ='v1',/>end",
    [.data("the"), .error("invalid character '=' in tag 'doc6'", 0, 10), .error("invalid tag 'doc6' dropped", 0, 17), .data("end")]),
("<doc7 attr='value'/>", [.open(name: "doc7", is_sc: true, attrs: ["attr": "value"])]),
("</ doc8 attr='value' attr2=\"value2\">",
    [.error("end tag 'doc8' cannot contain attributes", 0, 35), .close(name: "doc8")]),
("<doc9 attr  ='the ascii character \"'/>",
    [.open(name: "doc9", is_sc: true, attrs: ["attr": "the ascii character \""])]),
("<doc10 attr= \"<doc0 attr='value'/>\"/>",
    [.open(name: "doc10", is_sc: true, attrs: ["attr": "<doc0 attr='value'/>"])]),
("<doc11 attr \"misplaced\"=\"value\"/>",
    [.error("unexpected string literal in tag 'doc11'", 0, 12), .error("invalid tag 'doc11' dropped", 0, 32)]),
("<doc12 attr \"mispl'a>'ced\"=\"value\"/><body/>",
    [.error("unexpected string literal in tag 'doc12'", 0, 12), .error("invalid tag 'doc12' dropped", 0, 35), .open(name: "body", is_sc: true, attrs: [:])]),
("<doc13 attr \"mispl\"a>'ced\"=\"value\"/><body/>",
    [.error("unexpected string literal in tag 'doc13'", 0, 12), .error("invalid tag 'doc13' dropped", 0, 20), .data("'ced\"=\"value\"/>"), .open(name: "body", is_sc: true, attrs: [:])]),
("<doc14 attr#='value'/ \">\" q/><body>",
    [.error("invalid character '#' in tag 'doc14'", 0, 11), .error("invalid tag 'doc14' dropped", 0, 28), .open(name: "body", is_sc: false, attrs: [:])]),
("<doc15><!-- a comment --></doc16>", [.open(name: "doc15", is_sc: false, attrs: [:]), .close(name: "doc16")]),
("<doc17 <!-- a comment -->></doc18>", [.error("invalid character '<' in tag 'doc17'", 0, 7), .error("invalid tag 'doc17' dropped", 0, 24), .data(">"), .close(name: "doc18")])
]

run_tests(cases: test_cases)
