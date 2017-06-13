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

import Glibc

public
protocol XMLParser
{
    mutating
    func handle_data(data:[Unicode.Scalar], level:Int)
    mutating
    func handle_tag_start(name:String, namespace_uri:String?, attributes:[String: String], level:Int)
    mutating
    func handle_tag_start_end(name:String, namespace_uri:String?, attributes:[String: String], level:Int)
    mutating
    func handle_tag_end(name:String, namespace_uri:String?, level:Int)
    mutating
    func handle_error(_ message:String, line:Int, column:Int)
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

enum State
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

public
extension XMLParser
{
    private static
    func posix_path(_ path:String) -> String
    {
        guard let first_char:Character = path.first
        else
        {
            return path
        }
        var expanded_path:String = path
        if first_char == "~"
        {
            if expanded_path.count == 1 || expanded_path[expanded_path.index(after: expanded_path.startIndex)] == "/"
            {
                expanded_path = String(cString: getenv("HOME")) + String(expanded_path.dropFirst())
            }
        }
        return expanded_path
    }

    private mutating
    func open_text_file(_ posix_path:String) -> String?
    {
        guard let f:UnsafeMutablePointer<FILE> = fopen(posix_path, "rb")
        else
        {
            self.handle_error("could not open file stream '\(posix_path)'", line: 0, column: 0)
            return nil
        }
        defer { fclose(f) }

        let fseek_status:CInt = fseek(f, 0, SEEK_END)
        guard fseek_status == 0
        else
        {
            self.handle_error("fseek() on file '\(posix_path)' failed with error code \(fseek_status)", line: 0, column: 0)
            return nil
        }

        let n:CLong = ftell(f)
        guard 0 ..< CLong.max ~= n
        else
        {
            self.handle_error("ftell() on file '\(posix_path)' returned too large file size (\(n) bytes)", line: 0, column: 0)
            return nil
        }
        rewind(f)

        let buffer:UnsafeMutablePointer<CChar> = UnsafeMutablePointer<CChar>.allocate(capacity: n + 1) // leave room for sentinel
        defer { buffer.deallocate(capacity: n + 1) }

        let n_read = fread(buffer, MemoryLayout<CChar>.size, n, f)
        guard n_read == n
        else
        {
            self.handle_error("fread() on file '\(posix_path)' read \(n_read) characters out of \(n)", line: 0, column: n_read)
            return nil
        }

        buffer[n] = 0 // cap with sentinel
        return String(cString: buffer)
    }

    public mutating
    func parse(_ doc:String)
    {
        var data_buffer:[Unicode.Scalar] = [],
            str_buffer:String            = "",
            label_buffer:String          = "",
            name_buffer:String           = "",
            name_prefix:String?          = nil,
            attributes:[String: String]  = [:]

        var stack_level:Int                       = 0,
            namespaces:[(name:String, level:Int)] = [],
            namespace_uris:[String: [String]]     = [:]

        // bug in swift compiler prevents this from being computed property
        @inline(__always)
        func _context() -> String
        {
            return "attribute '\(label_buffer)' in tag '\(label_buffer)'"
        }

        var l:Int = 0,
            k:Int = 0

        @inline(__always)
        func _emit_tag(_ angle_bracket_group:AngleBracketGroup)
        {
            // bug in swift compiler prevents this from being computed property
            @inline(__always)
            func _namespace_uri() -> String?
            {
                if let name_prefix = name_prefix
                {
                    return namespace_uris[name_prefix]?.last
                }
                else
                {
                    return nil
                }
            }

            switch angle_bracket_group
            {
            case .initial:
                break
            case .start:
                // look for namespace declarations
                for (attribute, value):(String, String) in attributes
                {
                    guard let first_colon:String.CharacterView.Index = attribute.index(of: ":")
                    else
                    {
                        continue
                    }
                    guard attribute[..<first_colon] == "xmlns"
                    else
                    {
                        continue
                    }

                let namespace:String = String(attribute[attribute.index(after: first_colon)...])
                    namespaces.append((name: namespace, level: stack_level + 1))
                    if namespace_uris[namespace]?.append(value) == nil
                    {
                        namespace_uris[namespace] = [value]
                    }
                }

                self.handle_tag_start(name: name_buffer, namespace_uri: _namespace_uri(), attributes: attributes, level: stack_level)
                stack_level += 1
            case .start_end:
                self.handle_tag_start_end(name: name_buffer, namespace_uri: _namespace_uri(), attributes: attributes, level: stack_level)
            case .end:
                stack_level -= 1
                self.handle_tag_end(name: name_buffer, namespace_uri: _namespace_uri(), level: stack_level)

                for (namespace, level):(String, Int) in namespaces.reversed()
                {
                    guard level > stack_level
                    else
                    {
                        break
                    }

                    namespace_uris[namespace]?.removeLast()
                    if namespace_uris[namespace]?.isEmpty ?? false
                    {
                        namespace_uris[namespace] = nil
                    }
                }

            case let .empty(kind, l, k):
                self.handle_error("empty tag '\(kind)' ignored", line: l, column: k)
            case let .dropped(l, k):
                self.handle_error("invalid tag '\(name_buffer)' dropped", line: l, column: k)
            case .comment:
                break
            }
        }

        var state:State = .emit(.initial)
        var inside_end_tag:Bool = false
        var expected_str_delim:Unicode.Scalar = "\0"
        var unexpected_str_delim:Unicode.Scalar? = nil

        for u in doc.unicodeScalars
        {
            switch state
            {
            case .emit(let angle_bracket_group):
                _emit_tag(angle_bracket_group)

                label_buffer = ""
                name_buffer = ""
                name_prefix = nil
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
                    self.handle_data(data: data_buffer, level: stack_level)
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
                if u_previous == ":"
                {
                    name_prefix = name_prefix ?? name_buffer
                }

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
                    self.handle_error("unexpected '>' after \(_context())", line: l, column: k)
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
                    self.handle_error("unexpected '>' after \(_context())", line: l, column: k)
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
                    self.handle_error("unexpected '>' after '=' on \(_context())", line: l, column: k)
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
                    self.handle_error("unexpected '>' after '=' on \(_context())", line: l, column: k)
                    state = .emit(inside_end_tag ? .end : .start)
                }
                else if !u.is_xml_whitespace
                {
                    state = .invalid1(u, l, k)
                }
            case .string:
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
                        self.handle_error("end tag '\(name_buffer)' cannot contain attributes", line: l, column: k)
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
                    self.handle_error("unexpected string literal in tag '\(name_buffer)'", line: l_previous, column: k_previous)
                    if u != u_previous
                    {
                        unexpected_str_delim = u_previous
                    }
                    state = .invalid_etc
                }
                else
                {
                    self.handle_error("invalid character '\(u_previous)' in tag '\(name_buffer)'", line: l_previous, column: k_previous)
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
            self.handle_data(data: data_buffer, level: stack_level)
        default:
            self.handle_error("unexpected EOF", line: l, column: k)
        }
    }

    public mutating
    func parse(path:String)
    {
        guard let file_body:String = self.open_text_file(Self.posix_path(path))
        else
        {
            return
        }

        self.parse(file_body)
    }
}
