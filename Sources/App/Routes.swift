import Vapor

extension Droplet {
    func setupRoutes() throws {

        /// 首页
        get("/"){ req in
            return try self.view.make("index.html")
        }
        /// 用户协议
        get("protocol") { req in
            return try self.view.make("protocol.html")
        }
        /// 关于再书
        get("about") { req in
            return try self.view.make("about.html")
        }

        ///
        get("hello") { req in
            var json = JSON()
            try json.set("hello", "world")
            try json.set("uri", req)
            return json
        }

        /// 意见反馈
        post("feedback") { req in
            guard let userId = req.data[Feedback.Key.userId]?.int else {
                return try ApiRes.error(code: 1, msg: "miss userId")
            }
            guard let content = req.data[Feedback.Key.content]?.string else {
                return try ApiRes.error(code: 2, msg: "miss content")
            }
            let feedback = Feedback(content: content, userId: userId)
            try feedback.save()
            return try ApiRes.success(data: ["success": true])
        }

        group("book") { (router) in
            router.get("isbn", String.parameter) { req in
                let isbn = try req.parameters.next(String.self)
                let res =  try self.client.get("https://api.douban.com/v2/book/isbn/\(isbn)")
                return try ApiRes.success(data: ["info": res.json])
            }
            router.get("search") { req in
                // 搜索关键字
                if let searchKey = req.data["searchKey"]?.string {
                    let query = try Book.makeQuery().or({ (orGroup) in
                        try orGroup.filter(Book.Key.name, .contains, searchKey)
                        try orGroup.filter(Book.Key.isbn, .contains,searchKey)
                    })
                    return try Book.page(request: req, query: query)
                }
                // 搜索分类
                if let cateId = req.data["categoryId"]?.int {
                    let query = try Book.makeQuery().and({ (andGroup) in
                        try andGroup.filter(Book.Key.classifyId, cateId)
                        try andGroup.filter(Book.Key.state, .notEquals, 1) // 未审核的不显示
                    })
                    return  try Book.page(request: req, query: query)
                }
                return try Book.page(request: req)
            }

            // 这个 api 有点问题, 该用户下的所有书籍
            router.get("/", Int.parameter) { req in
                let userId = try req.parameters.next(Int.self)
                guard let user = try User.find(userId) else {
                    return try ApiRes.error(code: 1, msg: "user not found")
                }
                guard let pUserId = req.data["pid"]?.int else  {
                    return try ApiRes.error(code: 2, msg: "pid miss")
                }
                if userId == pUserId { // 用户自己访问自己的
                    let books = try user.createBooks()
                    return try ApiRes.success(data: ["books": books])
                } else { //
                    let books = try user.createBooks().filter({$0.state != 1}) // 除了未审核的都可以看
                    return try ApiRes.success(data: ["books": books])
                }
            }

            /// 通过 bookId 获取书籍信息
            router.get("/info", handler: { req in
                guard let bookId = req.data["bookId"]?.int else {
                    return try ApiRes.error(code: 1, msg: "miss bookId")
                }
                guard let book = try Book.find(bookId) else {
                    return try ApiRes.error(code: 2, msg: "not find book")
                }
                return try ApiRes.success(data: ["book": book])
            })
        }

        group("base"){ (router) in
            _ = ToolController(builder: router)
        }

        // /account/*
        group("account") { (builder) in
            _ = AccountController(builder: builder, droplet: self)
        }

        group("category") { (builder) in
            _ = CategoryController(builder: builder)
        }

        let authMiddleware = AuthMiddleware()
        group(authMiddleware) { (builder) in

            // 用户模块
            builder.group("user", handler: { (router) in
                _ = UserController(builder: router)
            })

            // 书本
            builder.group("book", handler: { (router) in
                _ = BookController(builder: router)
            })

            builder.group("tool"){ (router) in
                _ = ToolController(builder: router)
            }

            builder.group("favorite", handler: { (router) in
                _ = FavoriteController(builder: router)
            })

            builder.group("comment", handler: { (router) in
                _ = CommentController(builder: router)
            })
        }
    }
}
