/*
    Copyright 2017, Kelvin Ma (“taylorswift”), kelvin13ma@gmail.com

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
    func handle_data(data:[Unicode.Scalar])
    func handle_starttag(name:String, attributes:[String: String])
    func handle_startendtag(name:String, attributes:[String: String])
    func handle_endtag(name:String)
    func error(_ message:String, line:Int, column:Int)
}

extension Unicode.Scalar
{
    // NameStartChar  ::=   ":" | [A-Z] | "_" | [a-z] | [#xC0-#xD6] | [#xD8-#xF6] | [#xF8-#x2FF]
    //                    | [#x370-#x37D]   | [#x37F-#x1FFF]  | [#x200C-#x200D] | [#x2070-#x218F]
    //                    | [#x2C00-#x2FEF] | [#x3001-#xD7FF] | [#xF900-#xFDCF] | [#xFDF0-#xFFFD]
    //                    | [#x10000-#xEFFFF]
    var is_xml_name_start:Bool
    {
        return "a" ... "z" ~= self || "A" ... "Z" ~= self // [a-z], [A-Z]
        || self == ":" || self == "_" // ":", "_"

        || "\u{C0}"   ... "\u{D6}"   ~= self || "\u{D8}"   ... "\u{F6}"   ~= self
        || "\u{F8}"   ... "\u{2FF}"  ~= self || "\u{370}"  ... "\u{37D}"  ~= self
        || "\u{37F}"  ... "\u{1FFF}" ~= self || "\u{200C}" ... "\u{200D}" ~= self
        || "\u{2070}" ... "\u{218F}" ~= self || "\u{2C00}" ... "\u{2FEF}" ~= self
        || "\u{3001}" ... "\u{D7FF}" ~= self || "\u{F900}" ... "\u{FDCF}" ~= self
        || "\u{FDF0}" ... "\u{FFFD}" ~= self || "\u{10000}" ... "\u{EFFFF}" ~= self
    }


    // NameChar       ::=   NameStartChar | "-" | "." | [0-9] | #xB7 | [#x0300-#x036F] | [#x203F-#x2040]
    var is_xml_name:Bool
    {
        return "a" ... "z" ~= self || "A" ... "Z" ~= self || "0" ... ":" ~= self
        || self == "_" || self == "-" || self == "." || self == "\u{B7}"

        || "\u{0300}" ... "\u{036F}" ~= self || "\u{203F}" ... "\u{2040}" ~= self

        || "\u{C0}"   ... "\u{D6}"   ~= self || "\u{D8}"   ... "\u{F6}"   ~= self
        || "\u{F8}"   ... "\u{2FF}"  ~= self || "\u{370}"  ... "\u{37D}"  ~= self
        || "\u{37F}"  ... "\u{1FFF}" ~= self || "\u{200C}" ... "\u{200D}" ~= self
        || "\u{2070}" ... "\u{218F}" ~= self || "\u{2C00}" ... "\u{2FEF}" ~= self
        || "\u{3001}" ... "\u{D7FF}" ~= self || "\u{F900}" ... "\u{FDCF}" ~= self
        || "\u{FDF0}" ... "\u{FFFD}" ~= self || "\u{10000}" ... "\u{EFFFF}" ~= self
    }

    // S	   ::=   	(#x20 | #x9 | #xD | #xA)+
    var is_xml_whitespace:Bool
    {
        return self == " " || self == "\u{9}" || self == "\u{D}" || self == "\u{A}"
    }
}

public
func parse(_ doc:String, parser:Parser)
{
    enum XMLState
    {
        case outer_save(Unicode.Scalar), tag, e_tag, name_save(Unicode.Scalar)
        case c_exclam, c_hyphen1, comment, c_hyphen2, c_hyphen3
        case ignore1, se_tag, label(Unicode.Scalar)
        case ignore2, equals, ignore3, string, string_save(Unicode.Scalar), store_attrib, ignore4
        case invalid1(Unicode.Scalar, Int, Int), invalid_etc
        case emit(AngleBracketGroup)
    }

    enum AngleBracketGroup
    {
        case initial,
             start,
             start_end,
             end,
             empty(String, Int, Int),
             dropped(Int, Int),
             comment
    }

    var data_buffer:[Unicode.Scalar] = [],
        str_buffer:String            = "",
        label_buffer:String          = "",
        name_buffer:String           = "",
        attributes:[String: String]  = [:]

    var context:String
    {
        return "attribute '\(label_buffer)' in tag '\(label_buffer)'"
    }

    var l:Int = 0,
        k:Int = 0

    @inline(__always)
    func _emit_tag(_ angle_bracket_group:AngleBracketGroup)
    {
        switch angle_bracket_group
        {
        case .initial:
            break
        case .start:
            parser.handle_starttag(name: name_buffer, attributes: attributes)
        case .start_end:
            parser.handle_startendtag(name: name_buffer, attributes: attributes)
        case .end:
            parser.handle_endtag(name: name_buffer)
        case let .empty(kind, l, k):
            parser.error("empty tag '\(kind)' ignored", line: l, column: k)
        case let .dropped(l, k):
            parser.error("invalid tag '\(name_buffer)' dropped", line: l, column: k)
        case .comment:
            break
        }
    }

    var state:XMLState = .emit(.initial)
    var inside_end_tag:Bool = false
    var expected_str_delim:Unicode.Scalar = "\0"
    var unexpected_str_delim:Unicode.Scalar? = nil

    for u in doc.unicodeScalars
    {
        switch state
        {
        case .emit(let angle_bracket_group):
            _emit_tag(angle_bracket_group)

            str_buffer = ""
            label_buffer = ""
            name_buffer = ""
            attributes = [:]

            if u == "<"
            {
                state = .tag
            }
            else
            {
                state = .outer_save(u)
            }
        case .outer_save(let u_previous):
            data_buffer.append(u_previous)
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
            inside_end_tag = false

            if u.is_xml_name_start
            {
                state = .name_save(u)
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
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }
        case .e_tag:
            inside_end_tag = true

            if u.is_xml_name_start
            {
                state = .name_save(u)
            }
            else if u == ">"
            {
                state = .emit(.empty("</>", l, k))
            }
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }
        case .name_save(let u_previous):
            name_buffer.append(Character(u_previous))
            if u.is_xml_name
            {
                state = .name_save(u)
            }
            else if u.is_xml_whitespace
            {
                state = .ignore1
            }
            else if !inside_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if u == ">"
            {
                state = .emit(inside_end_tag ? .end : .start)
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore1:
            if u.is_xml_name_start
            {
                state = .label(u)
            }
            else if !inside_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if u == ">"
            {
                state = .emit(inside_end_tag ? .end : .start)
            }
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }
        case .se_tag:
            if u == ">"
            {
                state = .emit(.start_end)
            }
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }
        case .label(let u_previous):
            label_buffer.append(Character(u_previous))
            if u.is_xml_name
            {
                state = .label(u)
            }
            else if u == "="
            {
                state = .equals
            }
            else if u.is_xml_whitespace
            {
                state = .ignore2
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after \(context)", line: l, column: k)
                state = .emit(inside_end_tag ? .end : .start)
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
                state = .emit(inside_end_tag ? .end : .start)
            }
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }
        case .equals:
            if u == "\"" || u == "'"
            {
                expected_str_delim = u
                state = .string
            }
            else if u.is_xml_whitespace
            {
                state = .ignore3
            }
            else if u == ">"
            {
                parser.error("unexpected '>' after '=' on \(context)", line: l, column: k)
                state = .emit(inside_end_tag ? .end : .start)
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
                state = .emit(inside_end_tag ? .end : .start)
            }
            else if !u.is_xml_whitespace
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
                state = .string_save(u)
            }
        case .string_save(let u_previous):
            str_buffer.append(Character(u_previous))
            if u == expected_str_delim
            {
                state = .store_attrib
            }
            else
            {
                state = .string_save(u)
            }
        case .store_attrib:
            attributes[label_buffer] = str_buffer
            str_buffer   = ""
            label_buffer = ""
            if u.is_xml_whitespace
            {
                state = .ignore4
            }
            else if !inside_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if u == ">"
            {
                if inside_end_tag
                {
                    parser.error("end tag '\(name_buffer)' cannot contain attributes", line: l, column: k)
                    state = .emit(.end)
                }
                else
                {
                    state = .emit(.start)
                }
            }
            else if u.is_xml_name_start
            {
                state = .label(u)
            }
            else
            {
                state = .invalid1(u, l, k)
            }
        case .ignore4:
            if u.is_xml_name_start
            {
                state = .label(u)
            }
            else if !inside_end_tag && u == "/"
            {
                state = .se_tag
            }
            else if !u.is_xml_whitespace
            {
                state = .invalid1(u, l, k)
            }

        case let .invalid1(u_previous, l_previous, k_previous):
            assert(unexpected_str_delim == nil)
            if u_previous == "\"" || u_previous == "'"
            {
                parser.error("unexpected string literal in tag '\(name_buffer)'", line: l_previous, column: k_previous)
                if u != u_previous
                {
                    unexpected_str_delim = u_previous
                }
                state = .invalid_etc
            }
            else
            {
                parser.error("invalid character '\(u_previous)' in tag '\(name_buffer)'", line: l_previous, column: k_previous)
                if u == ">"
                {
                    state = .emit(.dropped(l, k))
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
                state = .emit(.dropped(l, k))
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
                state = .emit(.empty("<!->", l, k))
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
                state = .emit(.comment)
            }
            else if u != "-"
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
    case .emit(let angle_bracket_group):
        _emit_tag(angle_bracket_group)
    case .outer_save(let u_last):
        data_buffer.append(u_last)
        parser.handle_data(data: data_buffer)
    default:
        parser.error("unexpected EOF", line: l, column: k)
    }
}
