###### Common Problems

# Yelp

Scaling Reads

By[Evan King](https://www.linkedin.com/in/evan-king-40072280/)·PublishedJul 16, 2024·

easy

·

Asked at:

+1

## Understanding the Problem

**🍽️ What is [Yelp](https://www.yelp.com/)?** Yelp is an online platform that allows users to search for and review local businesses, restaurants, and services.

### [Functional Requirements](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#1-functional-requirements)

Some interviewers will start the interview by outlining the core functional requirements for you. Other times, you'll be tasked with coming up with them yourself. If you've used the product before, this should be relatively straight forward. However, if you haven't, it's a good idea to ask some questions of your interviewer to better understand the system.

Here is the set of functional requirements we'll focus on in this breakdown (this is also the set of requirements I lead candidates to when asking this question in an interview)

**Core Requirements**

1. Users should be able to search for businesses by name, location (lat/long), and category
2. Users should be able to view businesses (and their reviews)
3. Users should be able to leave reviews on businesses (mandatory 1-5 star rating and optional text)

**Below the line (out of scope):**

- Admins should be able to add, update, and remove businesses (we will focus just on the user)
- Users should be able to view businesses on a map
- Users should be recommended businesses relevant to them

FIRST QUESTION

What are the non-functional requirements?

Try it yourself first

We recommend you to practice the question yourself first to get instant personalized feedback as you go.

### [Non-Functional Requirements](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#2-non-functional-requirements)

**Core Requirements**

1. The system should have low latency for search operations (< 500ms)
2. The system should be highly available, eventual consistency is fine
3. The system should be scalable to handle 100M daily users and 10M businesses

**Below the line (out of scope):**

- The system should protect user data and adhere to GDPR
- The system should be fault tolerant
- The system should protect against spam and abuse

If you're someone who often struggles to come up with your non-functional requirements, take a look at this list of [common non-functional requirements](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#2-non-functional-requirements) that should be considered. Just remember, most systems are all these things (fault tolerant, scalable, etc) but your goal is to identify the unique characteristics that make this system challenging or unique.

Here is what you might write on the whiteboard:

Functional Requirements- search for businesses- view businesses & reviews- review a businessNon-functional Requirements- availability >> consistency - low latency search (<500ms)- scalable to 100M DAU & 10M businesses

Yelp Non-Functional Requirements

### Constraints

Depending on the interview, your interviewer may introduce a set of additional constraints. If you're a senior+ candidate, spend some time in the interview to identify these constraints and discuss them with your interviewer.

When I ask yelp, I'll introduce the constraint that **each user can only leave one review per business.**

## The Set Up

### [Defining the Core Entities](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#core-entities-2-minutes)

We recommend that you start with a broad overview of the primary entities. At this stage, it is not necessary to know every specific column or detail. We will focus on the intricacies, such as columns and fields, later when we have a clearer grasp. Initially, establishing these key entities will guide our thought process and lay a solid foundation as we progress towards defining the API.

Just make sure that you let your interviewer know your plan so you're on the same page. I'll often explain that I'm going to start with just a simple list, but as we get to the high-level design, I'll document the data model more thoroughly.

To satisfy our key functional requirements, we'll need the following entities:

1. **Business**: Represents a business or service listed on Yelp. Includes details like name, location, category, and average rating.
2. **User**: Represents a Yelp user who can search for businesses and leave reviews.
3. **Review**: Represents a review left by a user for a business, including rating and optional text.

In the actual interview, this can be as simple as a short list like this. Just make sure you talk through the entities with your interviewer to ensure you are on the same page.

Core Entities- Users- Businesses- Reviews

Yelp Entities

### [The API](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#4-api-or-system-interface)

The next step in the framework is to define the APIs of the system. This sets up a contract between the client and the server, and it's the first point of reference for the high-level design.

Your goal is to simply go one-by-one through the core requirements and define the APIs that are necessary to satisfy them. Usually, these map 1:1 to the functional requirements, but there are times when multiple endpoints are needed to satisfy an individual functional requirement.

To search for businesses, we'll need a GET endpoint that takes in a set of search parameters and returns a list of businesses.

```
// Search for businesses
GET /businesses?query&location&category&page -> Business[]
```

Whenever you have an endpoint that can return a large set of results, you should consider adding pagination to it. This minimizes the payload size and makes the system more responsive.

To view a business and its reviews, we'll need a GET endpoint that takes in a business ID and returns the business details and its reviews.

```
// View business details and reviews
GET /businesses/:businessId -> Business & Review[]
```

While this endpoint is enough, you could also split the business and reviews into two separate endpoints. This way we can have pagination on the reviews.

```
// View business details
GET /businesses/:businessId -> Business

// View reviews for a business
GET /businesses/:businessId/reviews?page= -> Review[]
```

To leave a review, we'll need a POST endpoint that takes in the business ID, the user ID, the rating, and the optional text, and creates a review.

```
// Leave a review
POST /businesses/:businessId/reviews
{
  rating: number,
  text?: string
}
```

## [High-Level Design](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#high-level-design-10-15-minutes)

We'll start our design by going one-by-one through our functional requirements and designing a single system to satisfy them. Once we have this in place, we'll layer on depth via our deep dives.

### 1) Users should be able to search for businesses

The first thing users do when they visit a Yelp-like site is search for a business. Search includes any combination of name or term, location, and category like restaurants, bars, coffee shops, etc.

We already laid out our API above of GET /businesses?query&location&category&page, now we just need to draw out a basic architecture that can satisfy this incoming request.

To enable users to search for businesses, we'll start with a basic architecture:

ClientAPI Gateway- authentication- rate limiting- routingBusiness ServiceDatabasesearch(term, loc, category)Business- id- name- description- location (lat/long)- address- category- ...

Yelp High-Level Design

1. **Client**: Users interact with the system through a web or mobile application.
2. **API Gateway**: Routes incoming requests to the appropriate services. In this case, the Business Service.
3. **Business Service**: Handles incoming search requests by processing query parameters and formulating database queries to retrieve relevant business information.
4. **Database**: Stores information about businesses such as name, description, location, category, etc.

When a user searches for a business:

1. The client sends a GET request to /businesses with the search parameters as optional query params.
2. The API Gateway routes this request to the Business Service.
3. The Business Service queries the Database based on the search criteria.
4. The results are returned to the client via the API Gateway.

### 2) Users should be able to view businesses

Once users have submitted their search, they'll be viewing a list of businesses via the search results page. The next user action is to click on a business to view it's details.

Once they do, the client will issue a GET /businesses/:businessId request to the API Gateway.

To handle this, we don't need to introduce any additional services. We can just have the API Gateway route the request to the Business Service. The Business Service will query the Database for the business details and then the reviews. For now, we'll keep reviews in the same database as the businesses, but we'll need to make sure to join the two tables.

###### Pattern: Scaling Reads

Given the massive read:write ratio, reading businesses is an perfect use case for the scaling reads pattern.

ClientAPI Gateway- authentication- rate limiting- routingBusiness ServiceDatabasesearch(term, loc, category)view(businessId)Business- id- name- description- location (lat/long)- address- category- ...Reviews- userId- businessId- rating- text

Yelp High-Level Design

A common question I receive is when to separate services. There is no hard and fast rule, but the main criteria I will use are (a) whether the functionality is closely related and (b) whether the services need to scale independently due to vastly different read/write patterns.

In this case, viewing a business and searching for a business are closely related, and the read patterns are similar (both read-heavy), so it makes sense to have this logic as part of the same service for now.

When a user views a business:

1. The client sends a GET request to /businesses/:businessId.
2. The API Gateway routes this to the Business Service.
3. The Business Service retrieves business details and reviews from the Database.
4. The combined information is returned to the client.

### 3) Users should be able to leave reviews on businesses

Lastly, given this is a review site, users will also want to leave reviews on businesses. This is just a mandatory 1-5 star rating and an optional text field. We won't worry about the constraints that a user can only leave one review per business yet, we'll handle that in our deep dives.

We'll need to introduce one new service, the Review Service. This will handle the creation and management of reviews. We separate this into a different service mainly because the usage pattern is significantly different. Users search/view for businesses a lot, but they hardly ever leave reviews. This insight actually becomes fairly crucial later on in the design, stay tuned.

ClientAPI Gateway- authentication- rate limiting- routingBusiness ServiceDatabasesearch(term, loc, category)view(businessId)Business- id- name- description- location (lat/long)- address- category- ...Reviews- userId- businessId- rating- textReview Servicereview(userId, businessId, rating, text?)

Yelp High-Level Design

When a user leaves a review:

1. The client sends a POST request to /businesses/:businessId/reviews with the review data.
2. The API Gateway routes this to the Review Service.
3. The Review Service stores it in the Database.
4. A confirmation is sent back to the client.

Should we separate the review data into its own database? Aren't all microservices supposed to have their own database?

The answer to this question is a resounding maybe. There are some microservice zealots who will argue this point incessantly, but the reality is that many systems, use the same database for multiple purposes and it's often times the simpler and, arguably, correct answer.

In this case, we have a very tiny amount of data, 10M businesses x 100 reviews each = 1TB. Modern databases can handle this easily in a single instance, so we don't even need to worry about sharding. Additionally, reviews and businesses are tightly coupled and we don't want to have to join across services to get the business details and reviews.

The counter argument is typically related to fault isolation and operational responsibility. We want to make sure that if the review database goes offline, we aren't left unable to search or view businesses. While this is a valid concern, we can mitigate it via other means like simple replication.

At the end of the day, it's a discussion of trade-offs with no single correct answer. I bias toward simplicity unless I can articulate a clear benefit to adding complexity and suggest you do the same if not already strongly principled on the matter.

Show More

## [Potential Deep Dives](https://www.hellointerview.com/learn/system-design/in-a-hurry/delivery#deep-dives-10-minutes)

At this point, we have a basic, functioning system that satisfies the functional requirements. However, there are a number of areas we could dive deeper into to improve the system's performance, scalability, and fault tolerance. Depending on your seniority, you'll be expected to drive the conversation toward these deeper topics of interest.

### 1) How would you efficiently calculate and update the average rating for businesses to ensure it's readily available in search results?

When users search for businesses, we don't show the full business details of course in the search results. Instead, we show partial data including things like the business name, location, and category. Importantly, we also want to show users the average rating of the business since this is often the first thing they look at when deciding on a business to visit.

Calculating the average rating on the fly for every search query would be terribly inefficient. Let's dive into a few approaches that can optimize this.

What about a message queue? Whenever I ask this question, particularly of senior candidates, most will propose we write incoming reviews to a message queue and then have a consumer update the average rating in a separate service. While this is a decent answer, it's important to note that this introduces additional complexity that, it can be argued, is not necessary given the write volume.

As we pointed out early, many people search/review businesses but very few actually leave reviews. We can estimate this read:write ratio at as much as 1000:1. With 100M users, that would mean only 100k writes per day, or 1 write per second. This is tiny. Modern databases can handle thousands of writes per second, so even accounting for surges, this will almost never be a problem.

Calling this out is the hallmark of a staff candidate and is a perfect example of where simplicity actually demonstrates seniority.

### 2) How would you modify your system to ensure that a user can only leave one review per business?

We need to implement a constraint that allows users to leave only one review per business. This constraint serves as a basic measure to prevent spam and abuse. For example, it stops competitors from repeatedly leaving negative reviews (such as 1-star ratings) on their rivals' businesses.

Here are some options.

Generally speaking, whenever we have a data constraint we want to enforce that constraint as close the persistence layer as possible. This way we can ensure our business logic is always consistent and avoid having to do extra work in the application layer.

### 3) How can you improve search to handle complex queries more efficiently?

This is the crux of the interview and where you'll want to be sure to spend the most time. Search is a fairly complex problem and different interviewers may introduce different constraints or nuances that change the design. I'll walk through a couple of them.

The challenge is that searching by latitude and longitude in a traditional database without a proper indexing is highly inefficient for large datasets. When using simple inequality comparisons (> lat and < lat, > long and < long) to find businesses within a bounding box, the database has to perform a full table scan, checking every single record against these conditions. This is also true when searching for terms in the business name or description. This would require a wild card search across the entire database via a LIKE clause.

```
// This query sucks. Very very slow.
SELECT * 
FROM businesses 
WHERE latitude > 10 AND latitude < 20 
AND longitude > 10 AND longitude < 20
AND name LIKE '%coffee%';
```

[](https://www.hellointerview.com/learn/system-design/deep-dives/proximity-search)

1. [](https://en.wikipedia.org/wiki/Geohash)[](https://en.wikipedia.org/wiki/Quadtree)[](https://en.wikipedia.org/wiki/R-tree)
2. [](https://en.wikipedia.org/wiki/Inverted_index)
3. [](https://en.wikipedia.org/wiki/B-tree)

[](https://www.hellointerview.com/learn/system-design/deep-dives/elasticsearch)

[](https://en.wikipedia.org/wiki/Change_data_capture)

[](https://postgis.net/)

[](https://www.postgresql.org/docs/current/pgtrgm.html)

In some cases, interviewers will ask that you don't use Elasticsearch as it simplifies the design too much. If this is the case, they're often looking for a few things in particular:

1. They want you to determine and be able to talk about the correct geospatial indexing strategy. Essentially, this usually involves weighing the tradeoffs between geohashing and quadtrees, though more complex indexes like R-trees could be mentioned as well if you have familiarity. In my opinion, between geohashing and quadtrees, I'd opt for quadtrees since our updates are incredibly infrequent and businesses are clustered into densely populated regions (like NYC).
2. Next, you'll want to talk about second pass filtering. This is the process by which you'll take the results of your geospatial query and further filter them by exact distance. This is done by calculating the distance between the user's lat/long and the business lat/long and filtering out any that are outside of the desired radius. Technically speaking, this is done with something called the Haversine formula, which is like the Pythagorean theorem but optimized for calculating distances on a sphere.
3. Lastly, interviewer will often be looking for you to articulate the sequencing of the phases. The goal here is to reduce the size of the search space as quickly as possible. Distance will typically be the most restrictive filter, so we want to apply that first. Once we have our smaller set of businesses, we can apply the other filters (name, category, etc) to that smaller set to finalize the results.

### 4) How would you modify your system to allow searching by predefined location names such as cities or neighborhoods?

For staff level candidates or senior candidates that moved quickly and accurately through the interview up until this point, I'll typically ask this follow up question to increase the complexity.

Our design currently supports searching based on a business's latitude and longitude. However, users often search using more natural language terms like city names or neighborhood names. For example, Pizza in NYC.

Notably, these location are not just zipcodes, states, or cities. They can also be more complex, like a neighborhood ie. The Mission in San Francisco.

The first realization should be that a simple radius from a center point is insufficient for this use case. This is because city or neighborhoods are not perfectly circular and can have wildly different shapes. Instead, we need a way to define a polygon for each location and then check if any of the businesses are within that polygon.

These polygons are just a list of points and come from a variety of sources. For example, [GeoJSON](https://geojson.org/) is a popular format for storing geographic data and includes functionality for working with polygons. They can also just be a list of coordinates that you can represent as a series of lat/long points.

We simply need a way to:

1. Go from a location name to a polygon.
2. Use that polygon to filter a set of businesses that exist within it.

Solving #1 is relatively straightforward. We can create a new table in our database that maps location names to polygons. These polygons can be sourced from various publicly available datasets ([Geoapify](https://www.geoapify.com/download-all-the-cities-towns-villages/) is one example).

Then, to implement this:

1. Create a locations table with columns for name (e.g., "San Francisco"), type (e.g., "city", "neighborhood"), and polygon (to store the geographic data).
2. Populate this table with data from the chosen sources.
3. Index the name column for efficient lookups.

This approach allows us to quickly translate a location name into its corresponding polygon for use in geographic queries.

Now what about #2, once we have a polygon how do we use it to filter businesses?

Conveniently, both Postgres via the PostGIS extension and Elasticsearch have functionality for working with polygons which they call [Geoshapes](https://postgis.net/docs/reference.html#Geography_Shapes) or [Geopoints](https://www.elastic.co/guide/en/elasticsearch/reference/current/geo-point.html) respectively.

In the case of Elasticsearch, we can simply add a new geo_shape field to our business documents and use the geo_shape query to find businesses that exist within a polygon.

```
{
  "query": {
    "geo_bounding_box": { 
      "location": {
        "top_left": {
          "lat": 42,
          "lon": -72
        },
        "bottom_right": {
          "lat": 40,
          "lon": -74
        }
      }
    }
  }
}
```

Doing this bounding box search on every request isn't that efficient though. We can do better.

Instead of filtering on bounding boxes for each request, we can pre-compute the areas for each business upon creation and store them as a list of location identifiers in our business table. These identifiers could be strings (like "san_francisco") or enums representing different areas.

For example, a business document in Elasticsearch might look like this:

```
{
  "id": "123",
  "name": "Pizza Place",
  "location_names": ["bay_area","san_francisco", "mission_district"],
  "category": "restaurant"
}
```

Now all we need is an inverted index on the location_names field via a "keyword" field in ElasticSearch

By pre-computing the encompassing areas we avoid doing them on every request and only need to do them once when the business is created.

## Final Design

After applying all the deep dives, we may end up with a final design that looks like this:

ClientAPI Gateway- authentication- rate limiting- routingBusiness ServiceDatabasesearch(term, loc, category)view(businessId)Business- id- name- description- location (lat/long)- address- category- locationStrings- avgRating- numRatings- ...Reviews- userId- businessId- rating- textReview Servicereview(userId, businessId, rating, text?)Elasticsearch- geospatial index for location- inverted index for full text- index on categoryCDCLocations- name- type- points (list of points making up the area)Add review and synchronouslyupdate avgRating & numRatings

Yelp Final Design

## [What is Expected at Each Level?](https://www.hellointerview.com/blog/the-system-design-interview-what-is-expected-at-each-level)

So, what am I looking for at each level?

### Mid-level

At mid-level, I'm mostly looking for a candidate's ability to create a working, high-level design while being able to reasonably answer my follow-up questions about average ratings and search optimizations. I don't expect them to know about database constraints necessarily, but I do want to see them problem solve and brainstorm ways to get the constraint closer to the persistence layer. I also don't expect in-depth knowledge of different types of indexing, but they should be able to apply the "correct" technologies to solve the problem.

### Senior

For senior candidates, I expect that you nail the majority of the deep dives with the exception of "search by name string." I'm keeping an eye on your tendency to over-engineer and want to see strong justifications for your choices. You should understand the different types of indexes needed and should be able to weigh tradeoffs to choose the most effective technology.

### Staff+

For staff candidates, I'm really evaluating your ability to recognize key insights and use them to derive simple solutions. Things like using Postgres extensions to avoid introducing a new technology (like Elasticsearch) and avoid the consistency issues, recognizing that the write throughput is tiny and thus we don't need a message queue. Identifying that the amount of data is also really small, so a simple read replica and/or cache is enough, no need to worry about sharding. Staff candidates are able to acknowledge what a complex solution could be and under what conditions it may be necessary, but articulate why, in this situation, the simple option suffices.