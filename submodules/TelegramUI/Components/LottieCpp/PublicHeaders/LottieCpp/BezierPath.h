#ifndef BezierPath_h
#define BezierPath_h

#ifdef __cplusplus

#include <LottieCpp/CurveVertex.h>
#include <LottieCpp/PathElement.h>
#include <LottieCpp/CGPath.h>

#include <vector>

namespace lottie {

struct BezierTrimPathPosition {
    double start;
    double end;
    
    explicit BezierTrimPathPosition(double start_, double end_);
};

class BezierPathContents: public std::enable_shared_from_this<BezierPathContents> {
public:
    explicit BezierPathContents(CurveVertex const &startPoint);
    
    BezierPathContents();
    
    explicit BezierPathContents(lottiejson11::Json const &jsonAny) noexcept(false);
    
    BezierPathContents(const BezierPathContents&) = delete;
    BezierPathContents& operator=(BezierPathContents&) = delete;
    
    lottiejson11::Json toJson() const;
    
    std::shared_ptr<CGPath> cgPath() const;
    
public:
    std::vector<PathElement> elements;
    std::optional<bool> closed;
    
    double length();
    
private:
    std::optional<double> _length;
    
public:
    void moveToStartPoint(CurveVertex const &vertex);
    void addVertex(CurveVertex const &vertex);

    void reserveCapacity(size_t capacity);
    void setElementCount(size_t count);
    void invalidateLength();
    
    void addCurve(Vector2D const &toPoint, Vector2D const &outTangent, Vector2D const &inTangent);
    void addLine(Vector2D const &toPoint);
    void close();
    void addElement(PathElement const &pathElement);
    void updateVertex(CurveVertex const &vertex, int atIndex, bool remeasure);
    
    /// Trims a path fromLength toLength with an offset.
    ///
    /// Length and offset are defined in the length coordinate space.
    /// If any argument is outside the range of this path, then it will be looped over the path from finish to start.
    ///
    /// Cutting the curve when fromLength is less than toLength
    /// x                    x                                 x                          x
    /// ~~~~~~~~~~~~~~~ooooooooooooooooooooooooooooooooooooooooooooooooo-------------------
    /// |Offset        |fromLength                             toLength|                  |
    ///
    /// Cutting the curve when from Length is greater than toLength
    /// x                x                    x               x                           x
    /// oooooooooooooooooo--------------------~~~~~~~~~~~~~~~~ooooooooooooooooooooooooooooo
    /// |        toLength|                    |Offset         |fromLength                 |
    ///
    std::vector<std::shared_ptr<BezierPathContents>> trim(double fromLength, double toLength, double offsetLength);
    
    // MARK: Private
    
    std::vector<std::shared_ptr<BezierPathContents>> trimPathAtLengths(std::vector<BezierTrimPathPosition> const &positions);
};

class BezierPath {
public:
    explicit BezierPath(CurveVertex const &startPoint);
    BezierPath();
    explicit BezierPath(lottiejson11::Json const &jsonAny) noexcept(false);
    
    lottiejson11::Json toJson() const;
    
    double length();

    void moveToStartPoint(CurveVertex const &vertex);
    void addVertex(CurveVertex const &vertex);
    void reserveCapacity(size_t capacity);
    void setElementCount(size_t count);
    void invalidateLength();
    void addCurve(Vector2D const &toPoint, Vector2D const &outTangent, Vector2D const &inTangent);
    void addLine(Vector2D const &toPoint);
    void close();
    void addElement(PathElement const &pathElement);
    void updateVertex(CurveVertex const &vertex, int atIndex, bool remeasure);
    
    /// Trims a path fromLength toLength with an offset.
    ///
    /// Length and offset are defined in the length coordinate space.
    /// If any argument is outside the range of this path, then it will be looped over the path from finish to start.
    ///
    /// Cutting the curve when fromLength is less than toLength
    /// x                    x                                 x                          x
    /// ~~~~~~~~~~~~~~~ooooooooooooooooooooooooooooooooooooooooooooooooo-------------------
    /// |Offset        |fromLength                             toLength|                  |
    ///
    /// Cutting the curve when from Length is greater than toLength
    /// x                x                    x               x                           x
    /// oooooooooooooooooo--------------------~~~~~~~~~~~~~~~~ooooooooooooooooooooooooooooo
    /// |        toLength|                    |Offset         |fromLength                 |
    ///
    std::vector<BezierPath> trim(double fromLength, double toLength, double offsetLength);
    
    std::vector<PathElement> const &elements() const;
    std::vector<PathElement> &mutableElements();
    std::optional<bool> const &closed() const;
    void setClosed(std::optional<bool> const &closed);
    std::shared_ptr<CGPath> cgPath() const;
    BezierPath copyUsingTransform(CATransform3D const &transform) const;
    
public:
    BezierPath(std::shared_ptr<BezierPathContents> contents);
    
private:
    std::shared_ptr<BezierPathContents> _contents;
};

class BezierPathsBoundingBoxContext {
public:
    BezierPathsBoundingBoxContext();
    ~BezierPathsBoundingBoxContext();
    
public:
    float *pointsX = nullptr;
    float *pointsY = nullptr;
    int pointsSize = 0;
};

CGRect bezierPathsBoundingBox(std::vector<BezierPath> const &paths);
CGRect bezierPathsBoundingBoxParallel(BezierPathsBoundingBoxContext &context, std::vector<BezierPath> const &paths);

}

#endif

#endif /* BezierPath_h */
