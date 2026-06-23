import Foundation

enum Preset: String, CaseIterable, Identifiable {
    case social, streaming, shopping, news, adult, ads

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .social: return "Social Media"
        case .streaming: return "Streaming"
        case .shopping: return "Shopping"
        case .news: return "News"
        case .adult: return "Adult"
        case .ads: return "Ads & Trackers"
        }
    }

    var domains: [String] {
        switch self {
        case .social:
            return ["facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com",
                    "reddit.com", "snapchat.com", "threads.net", "linkedin.com", "tumblr.com"]
        case .streaming:
            return ["youtube.com", "netflix.com", "hulu.com", "twitch.tv", "disneyplus.com",
                    "primevideo.com", "hbomax.com", "max.com"]
        case .shopping:
            return ["amazon.com", "ebay.com", "etsy.com", "aliexpress.com", "walmart.com",
                    "target.com", "bestbuy.com"]
        case .news:
            return ["cnn.com", "bbc.com", "nytimes.com", "theguardian.com", "foxnews.com",
                    "news.ycombinator.com"]
        case .adult:
            return ["pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com"]
        case .ads:
            return ["doubleclick.net", "googlesyndication.com", "googleadservices.com",
                    "ads.yahoo.com", "adservice.google.com"]
        }
    }

    var blockSet: BlockSet {
        BlockSet(id: rawValue, name: displayName, domains: domains, appBundleIds: [])
    }
}
