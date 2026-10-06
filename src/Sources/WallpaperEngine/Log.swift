import os

public enum Log {
    private static let subsystem = "com.christianbyars.InteractiveBackground"
    public static let importing = Logger(subsystem: subsystem, category: "import")
    public static let playback = Logger(subsystem: subsystem, category: "playback")
    public static let display = Logger(subsystem: subsystem, category: "display")
    public static let pause = Logger(subsystem: subsystem, category: "pause")
    public static let login = Logger(subsystem: subsystem, category: "login")
}
