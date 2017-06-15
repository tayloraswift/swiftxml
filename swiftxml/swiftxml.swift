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

struct UnicodeScalarCountingIterator:IteratorProtocol
{
    private
    let unicode_scalar_view:String.UnicodeScalarView

    private
    var current_scalar:Unicode.Scalar = "\0",
        next_position:String.UnicodeScalarView.Index

    private(set)
    var l:Int = 0,
        k:Int = -1

    init(_ unicode_scalar_view:String.UnicodeScalarView)
    {
        self.unicode_scalar_view = unicode_scalar_view
        self.next_position       = unicode_scalar_view.startIndex
    }

    mutating
    func next() -> Unicode.Scalar?
    {
        guard self.next_position != self.unicode_scalar_view.endIndex
        else
        {
            return nil
        }

        if self.current_scalar == "\n"
        {
            self.k  = 0
            self.l += 1
        }
        else
        {
            self.k += 1
        }

        self.current_scalar = self.unicode_scalar_view[self.next_position]
        self.next_position = self.unicode_scalar_view.index(after: self.next_position)
        return self.current_scalar
    }

    mutating // starts with [name_start_char]
    func read_name(after name_start_char:Unicode.Scalar) -> (Unicode.Scalar, [Unicode.Scalar])?
    {
        var buffer:[Unicode.Scalar] = [name_start_char]
        while let u:Unicode.Scalar = self.next()
        {
            if u.is_xml_name
            {
                buffer.append(u)
            }
            else
            {
                return (u, buffer)
            }
        }

        return nil
    }

    mutating // starts with [whitespace]
    func read_spaces(after _:Unicode.Scalar) -> Unicode.Scalar?
    {
        while let u:Unicode.Scalar = self.next()
        {
            if !u.is_xml_whitespace
            {
                return u
            }
        }

        return nil
    }

    mutating // starts with [-]
    func read_comment(after _:Unicode.Scalar) -> Unicode.Scalar?
    {
        while let u:Unicode.Scalar = self.next()
        {
            if u == "-"
            {
                guard let u_after_hyphen:Unicode.Scalar = self.next()
                else
                {
                    return nil
                }

                if u_after_hyphen == "-"
                {
                    return self.next()
                }
            }
        }

        return nil
    }

    mutating // starts with [string[0]]
    func read_string(_ str:[Unicode.Scalar], after _:Unicode.Scalar) -> (Unicode.Scalar, Bool)?
    {
        for u_str:Unicode.Scalar in str.dropFirst()
        {
            guard let u:Unicode.Scalar = self.next()
            else
            {
                return nil
            }

            if u_str != u
            {
                return (u, false)
            }
        }

        guard let u_after_str:Unicode.Scalar = self.next()
        else
        {
            return nil
        }
        return (u_after_str, true)
    }

    mutating // starts with "\"" or "'"
    func read_attribute_value(after quote:Unicode.Scalar) -> (Unicode.Scalar, [Unicode.Scalar])?
    {
        var buffer:[Unicode.Scalar] = []
        while let u:Unicode.Scalar = self.next()
        {
            if u == quote
            {
                guard let u_after_quote:Unicode.Scalar = self.next()
                else
                {
                    return nil
                }
                return (u_after_quote, buffer)
            }
            else
            {
                buffer.append(u)
            }
        }

        return nil
    }
}

enum State
{
    case initial,
         angle,
         data(Unicode.Scalar),
         revert(UnicodeScalarCountingIterator)
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

    private mutating
    func eof(iterator:UnicodeScalarCountingIterator)
    {
        self.handle_error("unexpected end of stream inside markup structure", line: iterator.l, column: iterator.k + 1)
    }

    public mutating
    func parse(_ str:String)
    {

        let unicode_scalars:String.UnicodeScalarView = str.unicodeScalars

        var iterator:UnicodeScalarCountingIterator = UnicodeScalarCountingIterator(unicode_scalars),
            state:State = .initial

        @inline(__always) // starts with [whitespace]
        func _read_attribute_vector(after first:Unicode.Scalar) -> (Unicode.Scalar, [String: String]?)?
        {

            var attributes:[String: String] = [:],
                u:Unicode.Scalar            = first

            while true
            {
                // space1
                guard let u_after_space1:Unicode.Scalar = iterator.read_spaces(after: u)
                else
                {
                    return nil
                }

                // name
                guard u_after_space1.is_xml_name_start
                else
                {
                    return (u_after_space1, attributes)
                }

                guard let (u_after_name, name):(Unicode.Scalar, [Unicode.Scalar]) = iterator.read_name(after: u_after_space1)
                else
                {
                    return nil
                }

                let name_str:String = String(name)
                guard attributes[name_str] == nil
                else
                {
                    self.handle_error("redefinition of attribute '\(name_str)'", line: iterator.l, column: iterator.k)
                    return (u_after_name, nil)
                }

                // space2 ?
                let u_after_space2:Unicode.Scalar
                if u_after_name.is_xml_whitespace
                {
                    guard let u_after_space:Unicode.Scalar = iterator.read_spaces(after: u_after_name)
                    else
                    {
                        return nil
                    }
                    u_after_space2 = u_after_space
                }
                else
                {
                    u_after_space2 = u_after_name
                }

                // equals
                guard u_after_space2 == "="
                else
                {
                    self.handle_error("unexpected '\(u_after_space2)' in attribute '\(String(name))'", line: iterator.l, column: iterator.k)
                    return (u_after_space2, nil)
                }
                guard let u_after_equals:Unicode.Scalar = iterator.next()
                else
                {
                    return nil
                }

                // space3?
                let u_after_space3:Unicode.Scalar
                if u_after_equals.is_xml_whitespace
                {
                    guard let u_after_space:Unicode.Scalar = iterator.read_spaces(after: u_after_equals)
                    else
                    {
                        return nil
                    }
                    u_after_space3 = u_after_space
                }
                else
                {
                    u_after_space3 = u_after_equals
                }

                // value
                guard u_after_space3 == "\"" || u_after_space3 == "'"
                else
                {
                    self.handle_error("unexpected '\(u_after_space3)' in attribute '\(String(name))'", line: iterator.l, column: iterator.k)
                    return (u_after_space3, nil)
                }
                guard let (u_after_value, value):(Unicode.Scalar, [Unicode.Scalar]) = iterator.read_attribute_value(after: u_after_space3)
                else
                {
                    return nil
                }


                attributes[name_str] = String(value)

                // space 1
                guard u_after_value.is_xml_whitespace
                else
                {
                    return (u_after_value, attributes)
                }

                u = u_after_value
            }
        }

        fsm: while true
        {
            switch state
            {
            case .initial:
                guard let u:Unicode.Scalar = iterator.next()
                else
                {
                    return
                }

                state = u == "<" ? .angle : .data(u)

            case .angle:
                let iterator_state:UnicodeScalarCountingIterator = iterator

                guard let u_after_angle:Unicode.Scalar = iterator.next()
                else
                {
                    self.eof(iterator: iterator)
                    return
                }

                if u_after_angle.is_xml_name_start
                {
                    guard let (u_after_name, name):(Unicode.Scalar, [Unicode.Scalar]) = iterator.read_name(after: u_after_angle)
                    else
                    {
                        self.eof(iterator: iterator)
                        return
                    }

                    guard let (u_after_attributes, attributes_ret):(Unicode.Scalar, [String: String]?) =
                    u_after_name.is_xml_whitespace ? _read_attribute_vector(after: u_after_name) : (u_after_name, [:])
                    else
                    {
                        self.eof(iterator: iterator)
                        return
                    }

                    guard let attributes:[String: String] = attributes_ret
                    else
                    {
                        state = .revert(iterator_state)
                        continue
                    }

                    if u_after_attributes == ">"
                    {
                        self.handle_tag_start(name: String(name), attributes: attributes)
                    }
                    else if u_after_attributes == "/"
                    {
                        guard let u_after_slash:Unicode.Scalar = iterator.next()
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }
                        guard u_after_slash == ">"
                        else
                        {
                            self.handle_error("unexpected '\(u_after_slash)' in empty tag '\(String(name))'", line: iterator.l, column: iterator.k)
                            state = .revert(iterator_state)
                            continue
                        }

                        self.handle_tag_empty(name: String(name), attributes: attributes)
                    }
                    else
                    {
                        self.handle_error("unexpected '\(u_after_attributes)' in start tag '\(String(name))'", line: iterator.l, column: iterator.k)
                        state = .revert(iterator_state)
                        continue
                    }
                }
                else if u_after_angle == "/"
                {
                    guard let u_after_slash:Unicode.Scalar = iterator.next()
                    else
                    {
                        self.eof(iterator: iterator)
                        return
                    }

                    guard u_after_slash.is_xml_name_start
                    else
                    {
                        self.handle_error("unexpected '\(u_after_slash)' in end tag ''", line: iterator.l, column: iterator.k)
                        state = .revert(iterator_state)
                        continue
                    }

                    guard let (u_after_name, name):(Unicode.Scalar, [Unicode.Scalar]) = iterator.read_name(after: u_after_slash)
                    else
                    {
                        self.eof(iterator: iterator)
                        return
                    }

                    // space ?
                    let u_after_space1:Unicode.Scalar
                    if u_after_name.is_xml_whitespace
                    {
                        guard let u_after_space:Unicode.Scalar = iterator.read_spaces(after: u_after_name)
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }
                        u_after_space1 = u_after_space
                    }
                    else
                    {
                        u_after_space1 = u_after_name
                    }

                    guard u_after_space1 == ">"
                    else
                    {
                        if u_after_space1.is_xml_name_start
                        {
                            self.handle_error("end tag '\(String(name))' cannot contain attributes", line: iterator.l, column: iterator.k)
                        }
                        else
                        {
                            self.handle_error("unexpected '\(u_after_space1)' in end tag '\(String(name))'", line: iterator.l, column: iterator.k)
                        }
                        state = .revert(iterator_state) // syntax error, drop to data
                        continue
                    }

                    self.handle_tag_end(name: String(name))
                }
                else if u_after_angle == "!"
                {
                    guard let u_after_exclam:Unicode.Scalar = iterator.next()
                    else
                    {
                        self.eof(iterator: iterator)
                        return
                    }
                    if u_after_exclam == "-"
                    {
                        guard let u_after_hyphen:Unicode.Scalar = iterator.next()
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }

                        guard u_after_hyphen == "-"
                        else
                        {
                            self.handle_error("unexpected '\(u_after_hyphen)' after '<!-'", line: iterator.l, column: iterator.k)
                            state = .revert(iterator_state)
                            continue
                        }

                        // reads the comment through to the '--'
                        guard let u_after_comment:Unicode.Scalar = iterator.read_comment(after: u_after_hyphen)
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }

                        guard u_after_comment == ">"
                        else
                        {
                            self.handle_error("unexpected double hyphen '--' inside comment body", line: iterator.l, column: iterator.k - 1)
                            state = .revert(iterator_state)
                            continue
                        }
                    }
                    else if u_after_exclam == "["
                    {
                        guard let (u_after_str, match):(Unicode.Scalar, Bool) = iterator.read_string(["[", "C", "D", "A", "T", "A"], after: u_after_exclam)
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }

                        guard match
                        else
                        {
                            self.handle_error("unexpected '\(u_after_str)' in CDATA marker", line: iterator.l, column: iterator.k)
                            state = .revert(iterator_state)
                            continue
                        }

                        self.handle_error("CDATA sections are unsupported", line: iterator.l, column: iterator.k)
                        state = .revert(iterator_state)
                        continue
                    }
                    else if u_after_exclam == "E"
                    {
                        guard let (u_after_str, match):(Unicode.Scalar, Bool) = iterator.read_string(["E", "L", "E", "M", "E", "N", "T"], after: u_after_exclam)
                        else
                        {
                            self.eof(iterator: iterator)
                            return
                        }

                        guard match
                        else
                        {
                            self.handle_error("unexpected '\(u_after_str)' in element declaration ''", line: iterator.l, column: iterator.k)
                            state = .revert(iterator_state)
                            continue
                        }

                        self.handle_error("element declarations are unsupported", line: iterator.l, column: iterator.k)
                        state = .revert(iterator_state)
                        continue
                    }
                }
                else
                {
                    self.handle_error("unexpected '\(u_after_angle)' after left angle bracket '<'", line: iterator.l, column: iterator.k)
                    state = .revert(iterator_state) // syntax error, drop to data
                    continue
                }

                state = .initial

            case .data(let first):
                var buffer:[Unicode.Scalar] = [first]
                while let u:Unicode.Scalar = iterator.next()
                {
                    guard u != "<"
                    else
                    {
                        self.handle_data(data: buffer)
                        state = .angle
                        continue fsm
                    }

                    buffer.append(u)
                }

                self.handle_data(data: buffer)
                return

            case .revert(let iterator_state):
                iterator = iterator_state
                state = .data("<")
            }
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
