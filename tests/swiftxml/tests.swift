import XML

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
    case close(name:String), error(String, Int, Int), data(String)
    
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
            return "\(sc ? "selfclosing" : "start") tag: \(name), attributes: \(_print_attributes(attrs))"
        case .close(let name):
            return "end tag: \(name)"
        case let .error(message, l, k):
            return "\u{001B}[0;33m(\(l + 1):\(k + 1)) Warning: \(message)\u{1B}[0m"
        case .data(let v):
            return v
        }
    }
}

class HTMLParser:Parser
{
    var output:[Token] = []
    func reset()
    {
        self.output = []
    }
    func handle_data(data:[UnicodeScalar])
    {
        self.output.append(.data(data.map{String($0)}.joined()))
    }
    func handle_starttag(name:String, attributes:[String: String])
    {
        self.output.append(.open(name: name, is_sc: false, attrs: attributes))
    }
    func handle_startendtag(name:String, attributes:[String: String])
    {
        self.output.append(.open(name: name, is_sc: true, attrs: attributes))
    }
    func handle_endtag(name:String)
    {
        self.output.append(.close(name: name))
    }
    func error(_ message:String, line:Int, column:Int)
    {
        self.output.append(.error(message, line, column))
    }
}

func print_tokens(_ tokens:[Token]) -> String
{
    return tokens.map{String(describing: $0)}.joined(separator: "\n")
}

public 
func run_tests(cases test_cases:[(String, [Token])], print_correct:Bool = true)
{
    let test_parser = HTMLParser()
    var passed:Int = 0
    for (i, (test_case, expected_result)) in test_cases.enumerated()
    {
        parse(test_case, parser: test_parser)
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

    if !test_cases.isEmpty
    {
        print("\u{001B}[1;32m\(passed)/\(test_cases.count) passed\u{1B}[0m")
    }
}
