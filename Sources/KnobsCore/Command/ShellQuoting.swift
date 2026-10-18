/// Quotes one argument the way a POSIX shell would need it, for showing and copying commands only.
/// Knobs never executes these strings (DEC-006).
public enum ShellQuoting {
    private static let safeCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")

    public static func quote(_ argument: String) -> String {
        if argument.isEmpty { return "''" }
        if argument.allSatisfy(safeCharacters.contains) { return argument }
        return "'" + argument.replacing("'", with: #"'\''"#) + "'"
    }
}
