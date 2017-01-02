/*
    Copyright 2017, Kelvin Ma, kelvinsthirteen@gmail.com

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

public
protocol Parser
{
    func handle_data(data:[UnicodeScalar])
    func handle_starttag(name:String, attributes:[String: String])
    func handle_startendtag(name:String, attributes:[String: String])
    func handle_endtag(name:String)
    func error(_ message:String, line:Int, column:Int)
}

// NameStartChar  ::=   ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF] | [#x370-#x37D] | [#x37F-#x1FFF] | [#x200C-#x200D] | [#x2070-#x218F] | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD] | [#x10000-#xEFFFF]

private
func _is_NSC(_ us:UnicodeScalar) -> Bool
{
    let u:UInt32 = us.value
    return 0x61...0x7A ~= u || 0x41...0x5A ~= u // [a-z], [A-Z]
    || u == 0x3A || u == 0x5F // ":", "_"
    || 0xC0...0xD6 ~= u || 0xD8...0xF6 ~= u || 0xF8...0x2FF ~= u || 0x370...0x37D ~= u || 0x37F...0x1FFF ~= u || 0x200C...0x200D ~= u || 0x2070...0x218F ~= u || 0x2C00...0x2FEF ~= u || 0x3001...0xD7FF ~= u || 0xF900...0xFDCF ~= u || 0xFDF0...0xFFFD ~= u || 0x10000...0xEFFFF ~= u
}

// NameChar       ::=   NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]

private
func _is_NC(_ us:UnicodeScalar) -> Bool
{
    let u:UInt32 = us.value
    return 0x61...0x7A ~= u || 0x41...0x5A ~= u // [a-z], [A-Z]
    || u == 0x3A || u == 0x5F // ":", "_"
    || 0x30...0x39 ~= u || u == 0x2D || u == 0x2E || u == 0xB7 // [0-9], "-", "."
    || 0x0300...0x036F ~= u || 0x203F...0x2040 ~= u
    || 0xC0...0xD6 ~= u || 0xD8...0xF6 ~= u || 0xF8...0x2FF ~= u || 0x370...0x37D ~= u || 0x37F...0x1FFF ~= u || 0x200C...0x200D ~= u || 0x2070...0x218F ~= u || 0x2C00...0x2FEF ~= u || 0x3001...0xD7FF ~= u || 0xF900...0xFDCF ~= u || 0xFDF0...0xFFFD ~= u || 0x10000...0xEFFFF ~= u
}

// S	   ::=   	(#x20 | #x9 | #xD | #xA)+

private
func _is_whitespace(_ us:UnicodeScalar) -> Bool
{
    return us == "\u{20}" || us == "\u{9}" || us == "\u{D}" || us == "\u{A}"
}

private
enum _XStates
{
    case outer_save(UnicodeScalar), tag, e_tag, name_save(Character)
    case c_exclam, c_hyphen1, comment, c_hyphen2, c_hyphen3
    case ignore1, se_tag, attr_L(Character)
    case ignore2, equals, ignore3, string, string_save(Character), store_attrib, ignore4
    case invalid1(UnicodeScalar, Int, Int), invalid_etc
    case emit(_Emission)
}
private
enum _Emission
{
    case initial, start, start_end, end, empty(String, Int, Int), dropped(Int, Int), comment
}

public
func parse(_ doc:String, parser:Parser)
{
    var data_buffer:[UnicodeScalar] = []
    var str_buffer:String = ""
    var label_buffer:String = ""
    var name_buffer:String = ""
    var attrib_buffer:[String: String] = [:]

    var context:String
    {
        return "attribute '\(label_buffer)' in tag '\(label_buffer)'"
    }

    var l:Int = 0
    var k:Int = 0

    func emit_tag(_ emission:_Emission)
    {
        switch emission
        {
        case .initial:
            break
        case .start:
            parser.handle_starttag(name: name_buffer, attributes: attrib_buffer)
        case .start_end:
            parser.handle_startendtag(name: name_buffer, attributes: attrib_buffer)
        case .end:
            parser.handle_endtag(name: name_buffer)
        case let .empty(kind, l_1, k_1):
            parser.error("empty tag '\(kind)' ignored", line: l_1, column: k_1)
        case let .dropped(l_1, k_1):
            parser.error("invalid tag '\(name_buffer)' dropped", line: l_1, column: k_1)
        case .comment:
            break
        }
    }

    var state:_XStates = .emit(.initial)
    var is_end_tag:Bool = false
    var expected_str_delim:UnicodeScalar = "\""
    var unexpected_str_delim:UnicodeScalar? = nil

    for u in doc.unicodeScalars
    {
        switch state
        {
        case .emit(let emission):
            emit_tag(emission)

            str_buffer = ""
            label_buffer = ""
            name_buffer = ""
            attrib_buffer = [:]

            if u == "<"
            {
                state = .tag
            }
            else
            {
                state = .outer_save(u)
            }
        case .outer_save(let U):
            data_buffer.append(U)
            if u == "<"
            {
                state = .tag
                parser.handle_data(data: data_buffer)
                data_buffer = []
            }
            else
            {
                state = .outer_save(u)
            }
        case .tag:
            is_end_tag = false

            if _is_NSC(u)
            {
                state = .name_save(Character(u))
            }
            else if u == "/"
            {
                state = .e_tag
            }
            else if u == "!"
            {
                state = .c_exclam
            }
            else if u == ">"
            {
                state = .emit(.empty("<>", l, k))
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .e_tag:
            is_end_tag = true

            if _is_NSC(u)
            {
                state = .name_save(Character(u))
            }
            else if u == ">"
            {
                state = .emit(.empty("</>", l, k))
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .name_save(let C):
            name_buffer.append(C)
            if _is_NC(u)
            {
                state = .name_save(Character(u))
            }
            else if _is_whitespace(u)
            {
                state = .ignore1
            }
            else if !is_end_tag && u == "/"
            {
                state =  .se_tag
            }
            else if u == ">"
            {
                state = .emit( is_end_tag ? .end : .start )
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore1:
            if _is_NSC(u)
            {
                state = .attr_L(Character(u))
            }
            else if !is_end_tag && u == "/"
            {
                state =  .se_tag
            }
            else if u == ">"
            {
                state = .emit( is_end_tag ? .end : .start )
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .se_tag:
            if u == ">"
            {
                state = .emit( .start_end )
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .attr_L(let C):
            label_buffer.append(C)
            if _is_NC(u)
            {
                state = .attr_L(Character(u))
            }
            else if u == "="
            {
                state = .equals
            }
            else if _is_whitespace(u)
            {
                state = .ignore2
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after \(context)", line: l, column: k)
                state = .emit( is_end_tag ? .end : .start )
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore2:
            if u == "="
            {
                state = .equals
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after \(context)", line: l, column: k)
                state = .emit( is_end_tag ? .end : .start )
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .equals:
            if u == "\"" || u == "'"
            {
                expected_str_delim = u
                state = .string
            }
            else if _is_whitespace(u)
            {
                state = .ignore3
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after '=' on \(context)", line: l, column: k)
                state = .emit( is_end_tag ? .end : .start )
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore3:
            if u == "\"" || u == "'"
            {
                expected_str_delim = u
                state = .string
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after '=' on \(context)", line: l, column: k)
                state = .emit( is_end_tag ? .end : .start )
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }
        case .string:
            assert(str_buffer == "")
            if u == expected_str_delim
            {
                state = .store_attrib
            }
            else
            {
                state = .string_save(Character(u))
            }
        case .string_save(let C):
            str_buffer.append(C)
            if u == expected_str_delim
            {
                state = .store_attrib
            }
            else
            {
                state = .string_save(Character(u))
            }
        case .store_attrib:
            attrib_buffer[label_buffer] = str_buffer
            str_buffer = ""
            label_buffer = ""
            if _is_whitespace(u)
            {
                state = .ignore4
            }
            else if !is_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if u == ">"
            {
                if is_end_tag
                {
                    parser.error("end tag '\(name_buffer)' cannot contain attributes", line: l, column: k)
                    state = .emit( .end )
                }
                else
                {
                    state = .emit( .start )
                }
            }
            else if _is_NSC(u)
            {
                state = .attr_L(Character(u))
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore4:
            if _is_NSC(u)
            {
                state = .attr_L(Character(u))
            }
            else if !is_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if !_is_whitespace(u)
            {
                state = .invalid1(u, l, k)
            }

        case let .invalid1(U, l_1, k_1):
            assert(unexpected_str_delim == nil)
            if U == "\"" || U == "'"
            {
                parser.error("unexpected string literal in tag '\(name_buffer)'", line: l_1, column: k_1)
                if u != U
                {
                 unexpected_str_delim = U
                }
                state = .invalid_etc
            }
            else
            {
                parser.error("invalid character '\(U)' in tag '\(name_buffer)'", line: l_1, column: k_1)
                if u == ">"
                {
                    state = .emit( .dropped(l, k) )
                }
                else
                {
                    if u == "\"" || u == "'"
                    {
                        unexpected_str_delim = u
                    }
                    state = .invalid_etc
                }
            }
        case .invalid_etc:
            if let quote = unexpected_str_delim
            {
                if u == quote
                {
                    unexpected_str_delim = nil
                }
            }
            else if u == "\"" || u == "'"
            {

                 unexpected_str_delim = u
            }
            else if u == ">"
            {
                state = .emit( .dropped(l, k) )
            }


        case .c_exclam:
            if u == "-"
            {
                state = .c_hyphen1
            }
            else if u == ">"
            {
                state = .emit(.empty("<!>", l, k))
            }
            else
            {
                name_buffer.append("!")
                state = .invalid1(u, l, k)
            }
        case .c_hyphen1:
            if u == "-"
            {
                state = .comment
            }
            else if u == ">"
            {
                state = .emit(.empty("<!>", l, k))
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .comment:
            if u == "-"
            {
                state = .c_hyphen2
            }
        case .c_hyphen2:
            if u == "-"
            {
                state = .c_hyphen3
            }
            else
            {
                state = .comment
            }
        case .c_hyphen3:
            if u == ">"
            {
                state = .emit( .comment )
            }
            else
            {
                state = .comment
            }
        }


        if u == "\n"
        {
            l += 1
            k = 0
        }
        else
        {
            k += 1
        }
    }

    switch state
    {
    case.emit(let emission):
        emit_tag(emission)
    case .outer_save(let U):
        data_buffer.append(U)
        parser.handle_data(data: data_buffer)
    default:
        parser.error("unexpected EOF", line: l, column: k)
    }
}
