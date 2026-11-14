enum ProfileDataCenter: Equatable {
    case statistics(Int)
    case profilePhoto(Int)

    init?(statistics: Int?, profilePhoto: Int?) {
        if let statistics, statistics > 0 {
            self = .statistics(statistics)
        } else if let profilePhoto, profilePhoto > 0 {
            self = .profilePhoto(profilePhoto)
        } else {
            return nil
        }
    }
}
