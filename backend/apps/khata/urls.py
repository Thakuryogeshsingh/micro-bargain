from django.urls import path

from . import views

app_name = "khata"

urlpatterns = [
    path("customers/", views.CustomerListView.as_view(), name="customers"),
    path("customers/<int:pk>/", views.CustomerDetailView.as_view(), name="customer"),
    path("customers/<int:pk>/entries/", views.EntryCreateView.as_view(), name="entries"),
]
