namespace Quizly.Domain;

/// <summary>FSRS memory state. Numbers match the FSRS reference implementation.</summary>
public enum FsrsState : short
{
    Learning = 1,
    Review = 2,
    Relearning = 3,
}

/// <summary>FSRS rating. Quizly only produces Again (Nevím) and Good (Vím).</summary>
public enum Rating : short
{
    Again = 1,
    Good = 3,
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
