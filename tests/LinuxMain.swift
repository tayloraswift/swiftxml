import XMLTests
import Glibc

let test_cases:[(String, [Token])] =
[
("", []),
("data", [.data("data")]),
("<doc>", [.open(name: "doc", is_sc: false, attrs: [:])]),
("< doc >", [.error("unexpected ' ' after left angle bracket '<'", 0, 1), .data("< doc >")]),
("</doc/>", [.error("unexpected '/' in end tag 'doc'", 0, 5), .data("</doc/>")]),
("</doc >", [.close(name: "doc")]),
("<doc  />", [.open(name: "doc", is_sc: true, attrs: [:])]),
("<doc  /  >", [.error("unexpected ' ' in empty tag 'doc'", 0, 7), .data("<doc  /  >")]),
("<0invalid >", [.error("unexpected '0' after left angle bracket '<'", 0, 1), .data("<0invalid >")]),
("<//>", [.error("unexpected '/' in end tag ''", 0, 2), .data("<//>")]),
("< // >", [.error("unexpected ' ' after left angle bracket '<'", 0, 1), .data("< // >")]),
("</>", [.error("unexpected '>' in end tag ''", 0, 2), .data("</>")]),
("<", [.error("unexpected end of stream inside markup structure", 0, 1)]),
("look! \n<> An empty tag!", [.data("look! \n"), .error("unexpected '>' after left angle bracket '<'", 1, 1), .data("<> An empty tag!")]),
("the<doc ='v1',/>end",
    [.data("the"), .error("unexpected '=' in start tag 'doc'", 0, 8), .data("<doc ='v1',/>end")]),
("<doc attr='value'/>", [.open(name: "doc", is_sc: true, attrs: ["attr": "value"])]),
("</ doc attr='value' attr2=\"value2\">",
    [.error("unexpected ' ' in end tag ''", 0, 2), .data("</ doc attr='value' attr2=\"value2\">")]),
("</doc attr='value' attr2=\"value2\">",
    [.error("end tag 'doc' cannot contain attributes", 0, 6), .data("</doc attr='value' attr2=\"value2\">")]),
("<doc attr  ='the ascii character \"'/>",
    [.open(name: "doc", is_sc: true, attrs: ["attr": "the ascii character \""])]),
("<doc attr= \"<doc attr='value'/>\"/>",
    [.open(name: "doc", is_sc: true, attrs: ["attr": "<doc attr='value'/>"])]),
("<doc attr \"misplaced\"=\"value\"/>",
    [.error("unexpected '\"' in attribute 'attr'", 0, 10), .data("<doc attr \"misplaced\"=\"value\"/>")]),
("<doc attr \"mispl\"a>'ced\"=\"value\"/><body/>",
    [.error("unexpected '\"' in attribute 'attr'", 0, 10), .data("<doc attr \"mispl\"a>'ced\"=\"value\"/>"), .open(name: "body", is_sc: true, attrs: [:])]),
("<doc attr#='value'/ \">\" q/><body>",
    [.error("unexpected '#' in attribute 'attr'", 0, 9), .data("<doc attr#='value'/ \">\" q/>"), .open(name: "body", is_sc: false, attrs: [:])]),
("<doc><!-- a comment --></doc>", [.open(name: "doc", is_sc: false, attrs: [:]), .close(name: "doc")]),
("<doc <!-- a comment -->></doc>", [.error("unexpected '<' in start tag 'doc'", 0, 5), .data("<doc "), .data(">"), .close(name: "doc")])
]

exit(run_tests(cases: test_cases) ? 0 : 1)
