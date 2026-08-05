extension Repository.Policy.Census {
    /// One census coordinate; sixteen fields, censusVersion 1.
    public struct Row: Sendable, Equatable {
        public var censusVersion: String
        public var repository: String
        public var headSha: String
        public var path: String
        public var coordinateKind: Kind
        public var coordinateId: String
        public var line: Int
        public var engine: String
        public var excerptSha256: String
        public var family: String
        public var intendedOwner: String
        public var disposition: String
        public var measurement: String
        public var cause: String
        public var generatedBy: String
        public var notes: String

        public init(
            censusVersion: String = "1",
            repository: String,
            headSha: String,
            path: String,
            coordinateKind: Kind,
            coordinateId: String,
            line: Int,
            engine: String,
            excerptSha256: String,
            family: String,
            intendedOwner: String,
            disposition: String,
            measurement: String = "MEASURED",
            cause: String = "",
            generatedBy: String = "repository-policy census",
            notes: String = ""
        ) {
            self.censusVersion = censusVersion
            self.repository = repository
            self.headSha = headSha
            self.path = path
            self.coordinateKind = coordinateKind
            self.coordinateId = coordinateId
            self.line = line
            self.engine = engine
            self.excerptSha256 = excerptSha256
            self.family = family
            self.intendedOwner = intendedOwner
            self.disposition = disposition
            self.measurement = measurement
            self.cause = cause
            self.generatedBy = generatedBy
            self.notes = notes
        }

        public var values: [String] {
            [censusVersion, repository, headSha, path,
             coordinateKind.rawValue, coordinateId, String(line), engine,
             excerptSha256, family, intendedOwner, disposition,
             measurement, cause, generatedBy, notes]
        }
    }
}
