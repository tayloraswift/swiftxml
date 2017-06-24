import XML
import Glibc

func _print_attributes(_ attributes:[String: String]) -> String
{
    let internal_str = Array(attributes).sorted(by: {$0.0 < $1.0})
    .map{"'\($0.0)': '\($0.1)'"}.joined(separator: ", ")
    return "{\(internal_str)}"
}

public
enum Token: Equatable, CustomStringConvertible
{
    case open(name:String, is_sc:Bool, attrs:[String: String])
    case close(name:String), error(String, Int, Int), data(String), pi(String, String)

    public
    static func == (lhs:Token, rhs:Token) -> Bool
    {
        switch (lhs, rhs)
        {
        case (let .open(name1, sc1, attrs1), let .open(name2, sc2, attrs2)):
            return name1 == name2 && sc1 == sc2 && attrs1 == attrs2
        case (.close(let name1), .close(let name2)):
            return name1 == name2
        case (let .error(message1, l1, k1), let .error(message2, l2, k2)):
            return message1 == message2 && (l1, k1) == (l2, k2)
        case (.data(let v1), .data(let v2)):
            return v1 == v2
        case (let .pi(target1, data1), let .pi(target2, data2)):
            return target1 == target2 && data1 == data2
        default:
            return false
        }
    }

    public
    var description:String
    {
        switch self
        {
        case let .open(name, sc, attrs):
            return "\(sc ? "empty" : "start") tag: \(name), attributes: \(_print_attributes(attrs))"
        case .close(let name):
            return "end tag: \(name)"
        case let .error(message, l, k):
            return "\u{001B}[0;33m(\(l + 1):\(k + 1)) Warning: \(message)\u{1B}[0m"
        case let .pi(target, data):
            return "processing instruction [\(target)]: '\(data)'"
        case .data(let v):
            return v
        }
    }
}

struct HTMLParser:XMLParser
{
    private(set)
    var output:[Token] = []

    mutating
    func reset()
    {
        self.output = []
    }

    mutating
    func handle_data(data:[Unicode.Scalar])
    {
        self.output.append(.data(String(data.map(Character.init))))
    }

    mutating
    func handle_tag_start(name:String, attributes:[String: String])
    {
        self.output.append(.open(name: name, is_sc: false, attrs: attributes))
    }

    mutating
    func handle_tag_empty(name:String, attributes:[String: String])
    {
        self.output.append(.open(name: name, is_sc: true, attrs: attributes))
    }

    mutating
    func handle_tag_end(name:String)
    {
        self.output.append(.close(name: name))
    }

    mutating
    func handle_processing_instruction(target:String, data: [Unicode.Scalar])
    {
        self.output.append(.pi(target, String(data.map(Character.init))))
    }

    mutating
    func handle_error(_ message:String, line:Int, column:Int)
    {
        self.output.append(.error(message, line, column))
    }
}

func print_tokens(_ tokens:[Token]) -> String
{
    return tokens.map{String(describing: $0)}.joined(separator: "\n")
}

public
func run_tests(cases test_cases:[(String, [Token])], print_correct:Bool = true) -> Bool
{
    var test_parser = HTMLParser()
    var passed:Int = 0
    for (i, (test_case, expected_result)) in test_cases.enumerated()
    {
        test_parser.parse(test_case)
        //print(test_parser.output.map{String(describing: $0)}.joined(separator: "\n"))
        //print()
        if test_parser.output == expected_result
        {
            print("\u{001B}[0;32m" + "test case \(i) passes!" + "\u{1B}[0m")
            if print_correct
            {
                print("\u{001B}[0;32m" + "produced output:" + "\u{1B}[0m")
                print(print_tokens(test_parser.output))
                print()
            }
            passed += 1
        }
        else
        {
            print("\u{001B}[0;31m" + "test case \(i) failed")
            print("expected output:" + "\u{1B}[0m")
            print(print_tokens(expected_result))
            print()
            print("\u{001B}[0;31m" + "produced output:" + "\u{1B}[0m")
            print(print_tokens(test_parser.output))
            print()
        }
        test_parser.reset()
    }

    var t0:Int = 0
    t0 = clock()
    test_parser.parse(path: "tests/gl.xml")
    print("time: \(clock() - t0)")
    /*
    print(test_parser.output[0 ... 13])
    print(test_parser.output.count)
    */
    
    if !test_cases.isEmpty
    {
        print("\u{001B}[1;32m\(passed)/\(test_cases.count) passed\u{1B}[0m")
    }

    return passed == test_cases.count
}
