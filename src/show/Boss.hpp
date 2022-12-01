#ifndef HEADER_show_Boss_hpp_ALREAD_INCLUDED
#define HEADER_show_Boss_hpp_ALREAD_INCLUDED

namespace show {

    class Boss
    {
    public:
        bool setup();

        bool draw();

    private:
        unsigned int width_ = 0;
        unsigned int height_ = 0;
    };

} // namespace show

#endif
