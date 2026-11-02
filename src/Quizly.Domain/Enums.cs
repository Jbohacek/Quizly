namespace Quizly.Domain;

/// <summary>FSRS memory state. Numbers match the FSRS reference implementation.</summary>
public enum FsrsState : short
{
    Learning = 1,
    Review = 2,
    Relearning = 3,
}

/// <summary>FSRS ratings: Nevím, Těžké, Vím, Snadné (#19).</summary>
public enum Rating : short
{
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
}

public enum PointsReason
{
    Review,
    Milestone,
    Claim,
    Refund,
}

public enum ClaimStatus
{
    Pending,
    Confirmed,
    Rejected,
}

public enum NotificationCategory
{
    Morning,
    Evening,
    LastCall,
    Milestone,
    Wishlist,
    Comeback,
}
