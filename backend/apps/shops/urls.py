from django.urls import path

from . import views

app_name = "shops"

urlpatterns = [
    path("nearby/", views.NearbyShopsView.as_view(), name="nearby"),
    path("leaderboard/", views.LeaderboardView.as_view(), name="leaderboard"),
    path("favorites/", views.FavoriteShopListView.as_view(), name="favorites"),
    path("<int:pk>/", views.ShopDetailView.as_view(), name="detail"),
    path("<int:pk>/favorite/", views.FavoriteShopView.as_view(), name="favorite"),
]
