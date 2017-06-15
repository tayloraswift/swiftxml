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
    func handle_data(data:[Unicode.Scalar])
    mutating
    func handle_tag_start(name:String, attributes:[String: String])
    mutating
    func handle_tag_empty(name:String, attributes:[String: String])
    mutating
    func handle_tag_end(name:String)
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

extension String
{
    init(_ buffer:[Unicode.Scalar])
    {
        self.init(buffer.map(Character.init))
    }
}

enum State
{
    case data(Unicode.Scalar),
         begin_markup,
         slash1,
         name(Unicode.Scalar),
         attributes,
         no_attributes,
         label(Unicode.Scalar),
         space1,
         equals,
         space2,
         attribute_value,
         slash2,
         end_markup,

         exclam,
         hyphen1,
         comment,
         hyphen2,
         hyphen3

//         question
}

enum Markup
{
    case none,
         start,
         empty,
         end,
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
    func parse(_ str:String)
    {
        var state:State                                = .end_markup,
            markup_context:Markup                      = .none,
            iterator:String.UnicodeScalarView.Iterator = str.unicodeScalars.makeIterator(),
            iterator_checkpoint:String.UnicodeScalarView.Iterator = iterator

        var data_buffer:[Unicode.Scalar]    = [],
            name_buffer:[Unicode.Scalar]    = [],
            label_buffer:[Unicode.Scalar]   = [],
            value_buffer:[Unicode.Scalar]   = [],
            attributes:[String: String]     = [:],
            string_delimiter:Unicode.Scalar = "\0"

        var position:(l:Int, k:Int)            = (0, 0),
            position_checkpoint:(l:Int, k:Int) = position

        @inline(__always)
        func _emit_tag()
        {
            switch markup_context
            {
            case .none:
                break
            case .start:
                self.handle_tag_start(name: String(name_buffer), attributes: attributes)
            case .empty:
                self.handle_tag_empty(name: String(name_buffer), attributes: attributes)
            case .end:
                self.handle_tag_end(name: String(name_buffer))
            case .comment:
                break
            }
        }

        @inline(__always)
        func _reset()
        {
            name_buffer      = []
            label_buffer     = []
            value_buffer     = []
            attributes       = [:]
            string_delimiter = "\0"

            iterator = iterator_checkpoint
            position = position_checkpoint
            state = .data("<")
        }

        while let u:Unicode.Scalar = iterator.next()
        {
            switch state
            {
            case .end_markup:
                _emit_tag()
                markup_context = .none

                name_buffer = []
                attributes  = [:]

                if u == "<"
                {
                    iterator_checkpoint = iterator
                    position_checkpoint = position
                    state = .begin_markup
                }
                else
                {
                    state = .data(u)
                }

            case .data(let u_previous):
                data_buffer.append(u_previous)
                if u == "<"
                {
                    iterator_checkpoint = iterator
                    position_checkpoint = position
                    self.handle_data(data: data_buffer)
                    data_buffer = []
                    state = .begin_markup
                }
                else
                {
                    state = .data(u)
                }

            case .begin_markup:
                markup_context = .start
                if u.is_xml_name_start
                {
                    state          = .name(u)
                }
                else if u == "/"
                {
                    state          = .slash1
                }
                else if u == "!"
                {
                    state          = .exclam
                }
                else
                {
                    self.handle_error("unexpected '\(u)' after left angle bracket '<'",
                                        line: position.l, column: position.k)
                    _reset()
                    continue
                }

            case .slash1:
                markup_context = .end
                guard u.is_xml_name_start
                else
                {
                    self.handle_error("unexpected '\(u)' in end tag ''",
                                        line: position.l, column: position.k)
                    _reset() // syntax error, drop to data
                    continue
                }

                state = .name(u)

            case .name(let u_previous):
                name_buffer.append(u_previous)
                if u.is_xml_name
                {
                    state = .name(u)
                }
                else if u.is_xml_whitespace
                {
                    state = markup_context == .start ? .attributes : .no_attributes
                }
                else if u == "/"
                {
                    guard markup_context == .start
                    else
                    {
                        self.handle_error("unexpected '/' in end tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }

                    state = .slash2
                }
                else if u == ">"
                {
                    state = .end_markup
                }
                else
                {
                    self.handle_error("unexpected '\(u)' in \(markup_context == .start ? "start" : "end") tag '\(String(name_buffer))'",
                                        line: position.l, column: position.k)
                    _reset()
                    continue
                }

            case .attributes:
                if u.is_xml_name_start
                {
                    state = .label(u)
                }
                else if u == "/"
                {
                    state = .slash2
                }
                else if u == ">"
                {
                    state = .end_markup
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        self.handle_error("unexpected '\(u)' in start tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }
                }

            case .no_attributes:
                if u == ">"
                {
                    state = .end_markup
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        if u.is_xml_name_start
                        {
                            self.handle_error("end tag '\(String(name_buffer))' cannot contain attributes",
                                                line: position.l, column: position.k)
                        }
                        else
                        {
                            self.handle_error("unexpected '\(u)' in end tag '\(String(name_buffer))'",
                                                line: position.l, column: position.k)
                        }
                        _reset()
                        continue
                    }
                }

            case .label(let u_previous):
                label_buffer.append(u_previous)

                if u.is_xml_name
                {
                    state = .label(u)
                }
                else if u == "="
                {
                    state = .equals
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        self.handle_error("unexpected '\(u)' in start tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }

                    state = .space1
                }

            case .space1:
                if u == "="
                {
                    state = .equals
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        self.handle_error("unexpected '\(u)' in start tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }
                }

            case .equals:
                if u == "\"" || u == "'"
                {
                    string_delimiter = u
                    state = .attribute_value
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        self.handle_error("unexpected '\(u)' in start tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }

                    state = .space2
                }

            case .space2:
                if u == "\"" || u == "'"
                {
                    string_delimiter = u
                    state = .attribute_value
                }
                else
                {
                    guard u.is_xml_whitespace
                    else
                    {
                        self.handle_error("unexpected '\(u)' in start tag '\(String(name_buffer))'",
                                            line: position.l, column: position.k)
                        _reset()
                        continue
                    }
                }

            case .attribute_value:
                if u == string_delimiter
                {
                    string_delimiter = "\0"
                    let label_str:String = String(label_buffer)

                    guard attributes[label_str] == nil
                    else
                    {
                        self.handle_error("redefinition of attribute '\(label_str)'", line: position.l, column: position.k)
                        _reset()
                        continue
                    }

                    attributes[label_str] = String(value_buffer)
                    label_buffer = []
                    value_buffer = []

                    state = .attributes
                }
                else
                {
                    value_buffer.append(u)
                }

            case .slash2:
                markup_context = .empty
                guard u == ">"
                else
                {
                    self.handle_error("unexpected '\(u)' in empty tag '\(String(name_buffer))'",
                                        line: position.l, column: position.k)
                    _reset()
                    continue
                }

                state = .end_markup

            case .exclam:
                if u == "-"
                {
                    state = .hyphen1
                }
                else
                {
                    self.handle_error("XML declarations are unsupported", line: position.l, column: position.k)
                    _reset()
                    continue
                }

            case .hyphen1:
                guard u == "-"
                else
                {
                    self.handle_error("unexpected '\(u)' after '<!-'", line: position.l, column: position.k)
                    _reset()
                    continue
                }

                state = .comment

            case .comment:
                markup_context = .comment
                if u == "-"
                {
                    state = .hyphen2
                }

            case .hyphen2:
                if u == "-"
                {
                    state = .hyphen3
                }
                else
                {
                    state = .comment
                }

            case .hyphen3:
                guard u == ">"
                else
                {
                    self.handle_error("unexpected double hyphen '--' inside comment body",
                                        line: position.l, column: position.k - 1)
                    _reset()
                    continue
                }

                state = .end_markup
            }

            if u == "\n"
            {
                position.l += 1
                position.k  = 0
            }
            else
            {
                position.k += 1
            }
        }

        switch state
        {
        case .end_markup:
            _emit_tag()
        case .data(let u_final):
            data_buffer.append(u_final)
            self.handle_data(data: data_buffer)
        default:
            self.handle_error("unexpected end of stream inside markup structure",
                                line: position.l, column: position.k)
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
